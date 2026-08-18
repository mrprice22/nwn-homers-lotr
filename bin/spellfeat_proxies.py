#!/usr/bin/env python3
"""spellfeat_proxies.py - per-class proxy rows for caster feats the client hides.

THE DEFECT (roadmap ll-bonus-feat-lists)
----------------------------------------
feat.2da's MINSPELLLVL column means "you must be able to cast spells of this
level". The CLIENT filters the level-up feat list on it. Under the NWNX MaxLevel
plugin the client resolves a caster's maximum castable spell level as **0** once
that class passes level 40 - the same clamp already documented in README.md
"Levels 41-60" for the spell-known picker. So every feat with MINSPELLLVL >= 1
silently vanishes from both the class-bonus and the general feat list.

Measured on the reporter's own character (pure Wizard 46): the three feats the
list still offered - Brew Potion, Craft Wand, Epic Spell - are exactly the three
with a blank MINSPELLLVL, and every feat he qualified for but could not see had
1 or 9. No counterexamples in either direction.

Barbarian, Fighter, Monk and Rogue lose nothing, which is why fighter and monk
looked healthy while wizard did not.

WHY A PROXY ROW
---------------
The column cannot simply be cleared: it is the same column that stops a level-3
wizard taking Maximize Spell, and clearing it would break levels 1-40 to fix
41-60. Nor can the requirement be restated in 2DA terms - `MinLevel` +
`MinLevelClass` name exactly ONE class per row (stock uses them for Weapon
Specialization: MinLevel 4, MinLevelClass 4), and there is no way to write
"Wizard 17 or Sorcerer 18 or Cleric 17 or Druid 17".

So the stock rows are left completely alone, and for the band where the stock
row is unreachable we add an inert PROXY row per (feat, class):

  * MinLevelClass = the class, MinLevel = 41. This is a BAND SELECTOR, not a
    restatement of the requirement. A class that has reached level 41 is at its
    own table's maximum spell level by definition, so the original requirement
    is satisfied by construction and no exploit exists.
  * Every other prerequisite column is copied VERBATIM from the stock row, so
    Automatic Still Spell I still demands Still Spell and Spellcraft 27.
  * MINSPELLLVL blank, so the broken client filter cannot see it.
  * The row is inert. unpacked/spellfeat_proxy_inc.nss grants the REAL feat.

Below 41 the stock row is offered and the proxy is hidden by MinLevel; at 41+
the stock row is hidden by the client bug and the proxy is offered. The player
is never shown both at once.

THE PAIRING INVARIANT - hold either row, hold both
--------------------------------------------------
A proxy and its stock row are different feat ids, so the engine would happily
offer one to a character already holding the other and let them waste the pick.
Both directions are real. The resolver therefore keeps them paired: proxy held
-> grant the real feat; real held -> grant the inert proxy. Because the engine
never offers a feat you already have, that alone closes the double-pick in both
directions, with no suppression of the stock rows.

NO NEW TLK STRINGS
------------------
A proxy points FEAT (name) and DESCRIPTION at the STOCK ROW'S OWN STRREFS, so it
reads exactly like the feat it stands in for and this feature adds nothing to
lotr.tlk. That is deliberate: it removes the hak/TLK co-publish coupling that
would otherwise make a stale client render 178 blank feat names, and it avoids
hand-transcribing 178 Bioware feat names that nothing could check. The cost is
that a character holding the feat shows it twice on the sheet - accepted, and
the reason the resolver never has to rename anything.

APPEND ONLY
-----------
A proxy's row index is a feat id, baked into a .bic the moment a character takes
it. PROXY_CLASSES fixes the emission order, so widening SHIPPED_CLASSES appends
rows and never renumbers the ones already published. Never reorder either list.
"""

from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HAK_2DA = REPO / "hak_2da"

BLANK = "****"

# The class level at which a proxy becomes selectable. Not the feat's
# requirement - see "WHY A PROXY ROW" above. 41 is the first level at which the
# client's clamp has made the stock row unreachable.
PROXY_MIN_LEVEL = 41

# Stock feat.2da ends at row 1115, and no stock cls_feat table can reference a
# feat id above that. So any FeatIndex at or above this floor in one of our
# class tables is a row we appended, and is safe to discard and regenerate.
PROXY_ROW_FLOOR = 1116


@dataclass(frozen=True)
class ProxyClass:
    name: str          # display name, for console output only
    class_id: int      # classes.2da row - what MinLevelClass holds
    suffix: str        # LABEL suffix, keeps proxy labels unique
    feat_table: str    # cls_feat_*.2da stem
    spgn_table: str    # cls_spgn_*.2da stem


# APPEND ONLY. Order fixes every proxy's feat id.
PROXY_CLASSES: list[ProxyClass] = [
    ProxyClass("Wizard",   10, "WIZ",  "cls_feat_wiz",   "cls_spgn_wiz"),
    ProxyClass("Sorcerer",  9, "SORC", "cls_feat_sorc",  "cls_spgn_sorc"),
    ProxyClass("Cleric",    2, "CLER", "cls_feat_cler",  "cls_spgn_cler"),
    ProxyClass("Druid",     3, "DRUID", "cls_feat_druid", "cls_spgn_dru"),
    ProxyClass("Bard",      1, "BARD", "cls_feat_bard",  "cls_spgn_bard"),
    ProxyClass("Paladin",   6, "PAL",  "cls_feat_pal",   "cls_spgn_pal"),
    ProxyClass("Ranger",    7, "RANG", "cls_feat_rang",  "cls_spgn_rang"),
]

# Which of them are actually emitted. Wizard alone is the probe: it fixes the
# reporting player's character outright and settles the one open risk - whether
# the client honours MinLevel above 40 at all, which stock never exercises
# (its only uses of the column sit at value 4). Widen to every class once UAT
# confirms proxies appear at 41+ and stay hidden at level 3.
SHIPPED_CLASSES = ["Wizard"]

# MINSPELLLVL values at or above this are "never selectable" sentinels rather
# than a real spell-level requirement - stock Sap carries 100. They are not a
# client-clamp casualty and must never be given a proxy.
SENTINEL_MINSPELLLVL = 10


@dataclass(frozen=True)
class Proxy:
    row: int                # feat id of the proxy row
    cls: ProxyClass
    stock_id: int           # feat id of the real feat it stands in for
    stock_label: str
    min_spell_level: int    # the requirement the stock row states
    list_value: str | None  # cls_feat table List column, None = general pool only


# ---------------------------------------------------------------------------
# 2DA reading
# ---------------------------------------------------------------------------

def read_2da(path: Path):
    """Return (preamble_lines, header_columns, {row: cells}, newline).

    Same contract as bin/gen-legendary-feats.py's reader, including keeping the
    file's own newline: the stock tables are CRLF and rewriting them with bare
    LF would make every untouched row differ.
    """
    raw = path.read_bytes()
    newline = "\r\n" if b"\r\n" in raw else "\n"
    lines = raw.decode("latin-1").splitlines()
    if len(lines) < 3:
        raise SystemExit(f"error: {path} is not a 2DA")
    preamble, header = lines[:3], lines[2].split()
    rows = {}
    for line in lines[3:]:
        cells = line.split()
        if cells and cells[0].isdigit():
            rows[int(cells[0])] = cells
    return preamble, header, rows, newline


def max_spell_level(cls: ProxyClass, class_level: int = PROXY_MIN_LEVEL) -> int:
    """Highest spell level this class can cast at `class_level`.

    Read from OUR cls_spgn_*.2da, not transcribed: bin/gen-caster-slots.py owns
    rows 40-59 and retuning the cadence there must move the proxy matrix with it.
    """
    _, header, rows, _ = read_2da(HAK_2DA / f"{cls.spgn_table}.2da")
    cells = rows.get(class_level - 1)
    if cells is None:
        raise SystemExit(
            f"error: {cls.spgn_table}.2da has no row for class level {class_level}")
    return int(cells[1 + header.index("NumSpellLevels")]) - 1


def gated_feats(header, rows) -> dict[int, int]:
    """{feat id: MINSPELLLVL} for every row the client clamp can hide."""
    position = 1 + header.index("MINSPELLLVL")
    out = {}
    for index, cells in rows.items():
        value = cells[position]
        if value.isdigit() and 1 <= int(value) < SENTINEL_MINSPELLLVL:
            out[index] = int(value)
    return out


def class_feat_entries(cls: ProxyClass) -> dict[int, str]:
    """{feat id: List} for every selectable entry in this class's feat table."""
    _, header, rows, _ = read_2da(HAK_2DA / f"{cls.feat_table}.2da")
    fi, li = 1 + header.index("FeatIndex"), 1 + header.index("List")
    granted = 1 + header.index("GrantedOnLevel")
    out = {}
    for cells in rows.values():
        if len(cells) <= max(fi, li, granted):
            continue
        if cells[li] not in ("0", "1", "3"):
            continue
        out[int(cells[fi])] = cells[li]
    return out


def granted_on_level(cls: ProxyClass) -> dict[int, str]:
    _, header, rows, _ = read_2da(HAK_2DA / f"{cls.feat_table}.2da")
    fi = 1 + header.index("FeatIndex")
    gi = 1 + header.index("GrantedOnLevel")
    return {int(c[fi]): c[gi] for c in rows.values() if len(c) > max(fi, gi)}


# ---------------------------------------------------------------------------
# The matrix
# ---------------------------------------------------------------------------

def proxies(first_row: int, feat_header, feat_rows) -> list[Proxy]:
    """Every proxy row, in append-only order, starting at `first_row`.

    Emit (class C, feat F) iff C can cast at F's required spell level once C
    reaches level 41, AND C can reach F today - either F is in C's cls_feat
    table, or F is flagged ALLCLASSESCANUSE.

    The first clause is what correctly denies Paladin, Ranger and Bard the
    Epic Spell Focus and Automatic-metamagic proxies: they never reach 9th-level
    spells, so the original requirement still bars them.
    """
    gated = gated_feats(feat_header, feat_rows)
    allclasses = 1 + feat_header.index("ALLCLASSESCANUSE")
    label = 1 + feat_header.index("LABEL")

    out, row = [], first_row
    for cls in PROXY_CLASSES:
        if cls.name not in SHIPPED_CLASSES:
            continue
        ceiling = max_spell_level(cls)
        in_table = class_feat_entries(cls)
        auto = granted_on_level(cls)
        for stock_id in sorted(gated):
            need = gated[stock_id]
            if need > ceiling:
                continue
            cells = feat_rows[stock_id]
            if stock_id in in_table:
                list_value = in_table[stock_id]
            elif cells[allclasses] == "1":
                list_value = None
            else:
                continue
            # A proxy for an auto-granted entry would hand the feat out on a
            # level rather than offer it, which is not what any of these are.
            if auto.get(stock_id, "-1") not in ("-1", BLANK):
                raise SystemExit(
                    f"error: {cls.feat_table} grants feat {stock_id} on a level "
                    f"(GrantedOnLevel {auto[stock_id]}); a proxy would change "
                    "when the player receives it")
            out.append(Proxy(row, cls, stock_id, cells[label], need, list_value))
            row += 1
    return out


def proxy_label(proxy: Proxy) -> str:
    """LABEL and (prefixed with FEAT_) the Constant column.

    Stock labels are inconsistent about the prefix - `StillSpell` but
    `FEAT_EPIC_AUTOMATIC_STILL_SPELL_1` - so strip it before adding the class
    suffix, or the Constant column comes out as FEAT_FEAT_EPIC_...
    """
    stem = proxy.stock_label
    if stem.startswith("FEAT_"):
        stem = stem[len("FEAT_"):]
    return f"{stem}_{proxy.cls.suffix}"
