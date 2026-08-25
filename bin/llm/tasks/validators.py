"""Pure-Python checks on generated text.

These exist so quality control costs nothing. Every check here is a rule a
second model call would otherwise have to enforce, and each was written against
a real failure observed in testing rather than imagined:

  * "strike with strikes"                   -> stutter()
  * a wrapping pair of quotes around the whole description -> no_wrapping_quotes()
  * smart quotes and em dashes from the model, where this repo's own hand-written
    descriptions use plain `--`                -> no_typographic()
  * the same ring text for the 400th ring    -> near_duplicates(), batch-level

Note what is deliberately NOT checked: non-ASCII in general. The module's own
descriptions contain real Tolkien orthography (Carn Dum with a circumflex), so a
blanket ASCII rule would reject correct text. Only the *typographic* characters
an LLM adds unbidden are rejected.
"""
from __future__ import annotations

import re

# Curly quotes, en/em dashes, ellipsis, non-breaking space. Not accented letters.
TYPOGRAPHIC = {
    "‘": "'", "’": "'", "“": '"', "”": '"',
    "–": "-", "—": "--", "…": "...", " ": " ",
    "′": "'", "″": '"', "«": '"', "»": '"',
}

MARKDOWN = re.compile(r"(\*\*|__|^\s*[-*]\s|^#{1,6}\s|`)", re.M)
WORD = re.compile(r"[A-Za-z][A-Za-z'À-ɏ-]*")
PROPER = re.compile(r"\b([A-Z][a-zÀ-ɏ]{2,}(?:\s+of\s+[A-Z][a-z]+)?)\b")

# Sentence-initial and other capitalised words that are not lore names.
COMMON_CAPS = {
    "The", "A", "An", "It", "Its", "This", "These", "Those", "They", "Their",
    "He", "She", "His", "Her", "Who", "When", "Where", "What", "Though",
    "Forged", "Wrought", "Carved", "Bound", "Once", "None", "No", "Not",
    "Some", "Many", "Each", "Every", "Upon", "Within", "Against", "Across",
    "Beneath", "Before", "After", "Long", "Old", "Ancient", "Yet", "But",
    "And", "Or", "For", "From", "With", "Without", "Such", "Here", "There",
    "Even", "Still", "Now", "Then", "Thus", "So", "One", "Two", "Three",
}


def clean(text: str, keep_newlines: bool = False) -> str:
    """Normalise what is safely normalisable. Run before validating.

    `keep_newlines` matters for anything that EDITS existing text rather than
    writing new prose. Collapsing whitespace turned a real conversation line,
    "Unequipt items?\nor\nEquipt items?", into a single run-on line -- the
    spelling fix was right and the layout was destroyed with it, silently.
    """
    for bad, good in TYPOGRAPHIC.items():
        text = text.replace(bad, good)
    if keep_newlines:
        text = re.sub(r"[^\S\n]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
    else:
        text = re.sub(r"\s+", " ", text).strip()
    # Models like to wrap the whole thing in quotes despite being told not to.
    while len(text) > 2 and text[0] in "\"'" and text[-1] == text[0]:
        text = text[1:-1].strip()
    return text


# -- individual checks; each returns a warning string or None --------------
def too_long(text: str, limit: int) -> str | None:
    if len(text) > limit:
        return f"too-long ({len(text)} > {limit})"
    return None


def too_short(text: str, limit: int = 40) -> str | None:
    if len(text) < limit:
        return f"too-short ({len(text)} < {limit})"
    return None


def no_typographic(text: str) -> str | None:
    found = sorted({c for c in text if c in TYPOGRAPHIC})
    if found:
        return "typographic-chars (" + " ".join(repr(c) for c in found) + ")"
    return None


def no_wrapping_quotes(text: str) -> str | None:
    if len(text) > 2 and text[0] in "\"'" and text[-1] == text[0]:
        return "wrapped-in-quotes"
    return None


def no_markdown(text: str) -> str | None:
    if MARKDOWN.search(text):
        return "markdown-syntax"
    return None


def no_digits(text: str) -> str | None:
    """Restating numeric bonuses is the single most common brief violation."""
    if re.search(r"\d", text):
        return "contains-digits"
    return None


def stutter(text: str) -> str | None:
    """Adjacent or near-adjacent repetition of the same stem.

    Checked WITHIN sentences only. Across a sentence boundary repetition is
    ordinary English -- "...who wields it. It commands..." was flagged as a
    doubled word until this split was added, which is exactly the kind of false
    positive that teaches a reviewer to ignore the warnings.
    """
    for sentence in re.split(r"[.!?]+", text):
        words = [w.lower() for w in WORD.findall(sentence)]
        for i in range(len(words) - 1):
            if words[i] == words[i + 1]:
                return f"repeated-word ({words[i]!r})"
        # "strike with strikes" -- same stem two words apart
        for i in range(len(words) - 2):
            a, b = words[i], words[i + 2]
            if len(a) > 4 and (a == b or a.rstrip("s") == b.rstrip("s")):
                return f"stem-echo ({a!r}/{b!r})"
    return None


# Canonical Tolkien proper nouns. This is a LotR module: a description that
# mentions Mordor or the Elves is not fabricating anything, and without this
# list nearly every generation carries an invented-name warning and the signal
# drowns. What we actually want to catch is invented SPECIFICS -- a smith who
# never existed, a forge-city that is not in the legendarium or in this module.
LORE_ALLOW = {
    # peoples
    "Elf", "Elves", "Elven", "Elvish", "Dwarf", "Dwarves", "Dwarven", "Orc",
    "Orcs", "Orcish", "Uruk", "Uruks", "Hobbit", "Hobbits", "Ent", "Ents",
    "Men", "Man", "Numenor", "Numenorean", "Easterling", "Easterlings",
    "Haradrim", "Wose", "Woses", "Troll", "Trolls", "Goblin", "Goblins",
    "Nazgul", "Wraith", "Wraiths", "Balrog", "Maia", "Valar", "Vala",
    "Istari", "Wizard", "Wizards", "Ranger", "Rangers", "Rohirrim", "Dunedain",
    # places
    "Mordor", "Gondor", "Rohan", "Shire", "Bree", "Rivendell", "Imladris",
    "Lothlorien", "Lorien", "Moria", "Khazad", "Isengard", "Fangorn",
    "Mirkwood", "Erebor", "Dale", "Angmar", "Arnor", "Eriador", "Gorgoroth",
    "Ithilien", "Anduin", "Misty", "Mountains", "Barrow", "Downs", "Weathertop",
    "Amon", "Sul", "Osgiliath", "Minas", "Tirith", "Morgul", "Helm", "Deep",
    "Edoras", "Belegost", "Nogrod", "Gundabad", "Carn", "Dum", "Fornost",
    "Beleriand", "Valinor", "Numenor", "Harad", "Rhun", "Forochel",
    # Ordinary English words that appear inside canonical place names ("the
    # Golden Wood", "the Grey Havens"). Flagging these adds noise without
    # catching anything -- a real fabrication is a distinctive coinage like
    # "Aerthwaite" or "Thandril", never a word like "Wood".
    "Golden", "Wood", "Woods", "Havens", "Haven", "Towers", "Tower", "Gate",
    "Gates", "Mountain", "River", "Hills", "Hill", "Marshes", "Forest",
    "Grey", "Gray", "White", "Black", "Red", "Brown", "Green", "Silver",
    "Hornburg", "Deeping", "Westfold", "Eastfold", "Anorien", "Lebennin",
    "Dunland", "Dunlending", "Lorien", "Cirith", "Ungol", "Udun", "Nurn",
    "Emyn", "Muil", "Rauros", "Nimrodel", "Bruinen", "Baranduin", "Gladden",
    # things and eras
    "Ring", "Rings", "Power", "Silmaril", "Silmarils", "Mithril", "Westernesse",
    "Age", "Ages", "First", "Second", "Third", "Dark", "Lord", "Enemy",
    "Shadow", "West", "East", "North", "South", "Free", "Peoples", "Fellowship",
    # named figures common enough to be safe flavour
    "Sauron", "Morgoth", "Melkor", "Gandalf", "Saruman", "Elendil", "Isildur",
    "Feanor", "Celebrimbor", "Eregion", "Durin",
}


def _is_lore(word: str) -> bool:
    """Allowlist match, tolerant of adjectival forms (Gondor -> Gondorian)."""
    if word in LORE_ALLOW:
        return True
    return any(len(root) >= 4 and word.startswith(root) for root in LORE_ALLOW)


def invented_names(text: str, context: str) -> str | None:
    """Proper nouns that appear nowhere in the prompt context.

    This is the guard against fabricated Tolkien lore -- the model happily
    attributes a random dagger to a named smith of a named city otherwise.
    """
    haystack = context.lower()
    unknown = []
    # A capital at the start of a sentence says nothing about proper-nounhood --
    # "Crafted from supple leather" tripped this before the offsets were checked.
    sentence_starts = {0}
    for m in re.finditer(r"[.!?]\s+", text):
        sentence_starts.add(m.end())
    for match in PROPER.finditer(text):
        if match.start() in sentence_starts:
            continue
        head = match.group(1).split()[0]
        if head in COMMON_CAPS or _is_lore(head):
            continue
        whole = match.group(1)
        if whole.lower() in haystack or head.lower() in haystack:
            continue
        unknown.append(whole)
    if unknown:
        return "invented-name (" + ", ".join(sorted(set(unknown))[:3]) + ")"
    return None


def forbidden_phrases(text: str, phrases: tuple[str, ...]) -> str | None:
    low = text.lower()
    hit = [p for p in phrases if p.lower() in low]
    if hit:
        return "forbidden-phrase (" + ", ".join(hit) + ")"
    return None


# -- batch-level ----------------------------------------------------------
def _shingles(text: str, n: int = 4) -> set[str]:
    words = [w.lower() for w in WORD.findall(text)]
    return {" ".join(words[i:i + n]) for i in range(max(0, len(words) - n + 1))}


def near_duplicates(texts: dict[str, str], threshold: float = 0.5) -> dict[str, tuple[str, float]]:
    """{key: (other_key, similarity)} for texts too close to an earlier one.

    At two thousand items the real failure is not a bad description, it is four
    hundred interchangeable ones. Nothing else in the pipeline sees that, because
    every single item looks fine on its own.

    Inverted index over 4-word shingles, so this stays linear in practice rather
    than comparing every pair.
    """
    index: dict[str, list[str]] = {}
    shingles = {k: _shingles(v) for k, v in texts.items()}
    dupes: dict[str, tuple[str, float]] = {}
    for key in texts:
        mine = shingles[key]
        if not mine:
            continue
        counts: dict[str, int] = {}
        for sh in mine:
            for other in index.get(sh, ()):
                counts[other] = counts.get(other, 0) + 1
        if counts:
            best, hits = max(counts.items(), key=lambda kv: kv[1])
            score = hits / min(len(mine), len(shingles[best]))
            if score >= threshold:
                dupes[key] = (best, round(score, 3))
        for sh in mine:
            index.setdefault(sh, []).append(key)
    return dupes


def priority(warnings: list[str], confidence: float | None, dupe_score: float = 0.0) -> float:
    """Review-priority score, 0..1+. Higher means look at this one first.

    Deterministic signals dominate; the model's self-reported confidence is a
    weak tiebreaker (in testing it did separate a stuttered generation from two
    clean ones, but only by 0.1).
    """
    score = 0.35 * len(warnings) + 0.5 * dupe_score
    if confidence is not None:
        score += 0.25 * (1.0 - max(0.0, min(1.0, confidence)))
    return round(min(score, 2.0), 3)


# Function words and unavoidable domain nouns. Their recurrence says nothing
# about style, and leaving them in buries the words that do.
TIC_STOPWORDS = {
    "that", "this", "with", "from", "upon", "into", "onto", "have", "been",
    "were", "when", "what", "which", "them", "they", "their", "there", "then",
    "than", "some", "such", "over", "under", "about", "against", "would",
    "could", "each", "very", "much", "more", "most", "like", "even", "still",
    "only", "other", "these", "those", "your", "yours", "will", "shall",
}


def tics(texts: dict[str, str], top: int = 6) -> list[str]:
    """Batch-level stylistic tics: phrasing the model reaches for too often.

    near_duplicates() compares whole descriptions and misses this. A batch can
    have no two similar descriptions and still open sixteen of them with "A
    heavy", or work "feels ... upon the" into half of them. Nobody notices at
    item level -- each one reads fine -- and everybody notices when they have
    examined thirty items in a row.

    This does not gate anything. It is a report, so the prompt can be fixed
    before a 2000-item batch bakes the tic into the module.
    """
    if len(texts) < 8:
        return []
    total = len(texts)
    openings: dict[str, int] = {}
    words: dict[str, int] = {}
    for text in texts.values():
        toks = [w.lower() for w in WORD.findall(text)]
        if len(toks) >= 2:
            key = " ".join(toks[:2])
            openings[key] = openings.get(key, 0) + 1
        for word in set(toks):
            if len(word) > 3 and word not in TIC_STOPWORDS:
                words[word] = words.get(word, 0) + 1

    out = []
    for phrase, count in sorted(openings.items(), key=lambda kv: -kv[1])[:top]:
        if count / total >= 0.15 and count > 2:
            out.append(f"{count}/{total} open with {phrase!r}")
    for word, count in sorted(words.items(), key=lambda kv: -kv[1])[:top]:
        if count / total >= 0.35 and count > 3:
            out.append(f"{count}/{total} contain {word!r}")
    return out


# Capability claims, and the properties that would justify them. The point is
# not to police flavour -- "moss-dyed leather, worn soft by forest miles" is
# fine -- but to stop the text asserting a GAME capability the item lacks. The
# case that prompted this: boots granting only AC and Damage Reduction whose
# description promised the wearer could "navigate the shadows of the deep woods
# without alerting the slightest prey".
CLAIMS: dict[str, tuple[str, str]] = {
    "stealth": (
        # Written out at length deliberately. The case this exists for --
        # "footsteps falling as softly as autumn leaves ... without alerting the
        # slightest prey" -- uses none of the obvious words, so a short pattern
        # passed it clean.
        r"\b(silent|silently|soundless|noiseless|unheard|stealth\w*|sneak\w*|"
        r"unnotic\w+|undetect\w+|without a sound|makes? no sound|"
        r"unseen by|pass(?:es|ing)? unseen|go(?:es)? unseen|"
        r"without (?:alerting|waking|rousing|disturbing)|"
        r"(?:foot(?:step|fall)s?|tread|stride)\w*[^.]{0,30}?"
        r"(?:soft\w*|light\w*|quiet\w*|silent\w*|whisper\w*)|"
        r"(?:soft\w*|light\w*|quiet\w*)[^.]{0,20}?(?:foot(?:step|fall)s?|tread))\b",
        r"Hide|Move Silently|Invisibilit|Dexterity|Skill Bonus",
    ),
    "speed": (
        r"\b(swift\w*|hasten\w*|quicken\w*|fleet(?!ing)|nimbl\w+|"
        r"tireless|untiring)\b",
        # Improved Evasion and Freedom of Movement are as good a warrant for
        # "nimble" as Dexterity is; without them a chitin carapace granting
        # Improved Evasion was flagged for saying it moved lightly.
        r"Haste|Movement|Dexterity|Monk|Speed|Regenerat|Evasion|Free Action|"
        r"Feat: (?:Dodge|Mobility|Spring Attack)",
    ),
    "healing": (
        r"\b(heals?|healing|knits? (?:flesh|wounds)|mends? (?:flesh|wounds)|"
        r"wounds close|closes? wounds)\b",
        # A book that casts Restoration and Remove Disease is a healing item by
        # any reading; the first pass flagged one for saying so.
        r"Regenerat|Vampiric|Cure|Heal|Bonus Spell|Restoration|Remove Disease|"
        r"Remove Blindness|Remove Curse|Neutralize Poison|Positive|Raise Dead|"
        r"Resurrection|Bonus Feat: (?:Great Fortitude)",
    ),
    "sight": (
        r"\b(see in the dark|darkvision|true sight|sees? the unseen|"
        r"pierces? the (?:gloom|dark))\b",
        r"Darkvision|True See|Ultravision|Spot|Light|Wisdom",
    ),
}

# Phrases that match a claim pattern but do not assert anything about the bearer.
# Both were found by measuring against real generated text, and without them the
# check reports roughly three times as many problems as it should.
CLAIM_EXCEPTIONS = re.compile(
    r"\bunseen (?:world|realm|threads|hand|malice|foe|enem\w+|thing)\b"   # spirits, not stealth
    r"|\b(?:foe|foes|enem\w+|prey|quarry|opponent\w*)\b[^.]{0,24}\b"
    r"(?:nimbl\w+|swift\w*|fleet)\b"                                      # describes the ENEMY
    r"|\b(?:nimbl\w+|swift\w*|fleet)\b[^.]{0,24}\b(?:foe|foes|enem\w+|prey)\b",
    re.I,
)


def unfounded_claims(text: str, properties: str) -> str | None:
    """Capabilities the text asserts that the property list does not grant."""
    if not properties:
        return None
    hits = []
    for kind, (claim, justify) in CLAIMS.items():
        if re.search(justify, properties, re.I):
            continue
        for match in re.finditer(claim, text, re.I):
            window = text[max(0, match.start() - 40): match.end() + 40]
            if CLAIM_EXCEPTIONS.search(window):
                continue
            hits.append(kind)
            break
    if hits:
        return "unfounded-claim (" + ", ".join(sorted(set(hits))) + ")"
    return None
