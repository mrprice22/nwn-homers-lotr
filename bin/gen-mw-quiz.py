#!/usr/bin/env python3
"""Generate every consumer of the MeaningWave quiz bank from mw_quiz_bank.yaml.

`mw_quiz_bank.yaml` (repo root) is the SINGLE SOURCE OF TRUTH for the questions.
This script derives, and `--check` verifies, all four downstream artifacts so they
can never drift:

  * mw_quiz_bank.json          -- browser-native twin the wiki quiz engine reads
  * unpacked/mw_quiz_data.nss  -- the compiled-in bank the game uses (MW_*Row switch)
  * MeaningWave.md             -- the "Quiz question banks (answer key)" section
  * unpacked/mw_<guide>_m.dlg.json (x7) -- the quiz conversations (flavour lives here,
                                  not in the YAML; questions are injected at runtime
                                  via custom tokens, so they are NOT in the dlg files)

The runtime engine (unpacked/mw_quiz_inc.nss) is unchanged: it calls
MW_QRow(guide, i) for a '~'-packed "question~correct~wrong1~wrong2~wrong3" row.

Usage:
    python3 bin/gen-mw-quiz.py            # write all artifacts from the YAML
    python3 bin/gen-mw-quiz.py --check    # verify on-disk artifacts match (CI gate)
"""
import argparse
import json
import os
import re
import sys

import yaml

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(REPO, "unpacked")
BANK_YAML = os.path.join(REPO, "mw_quiz_bank.yaml")
BANK_JSON = os.path.join(REPO, "mw_quiz_bank.json")
DATA_NSS = os.path.join(UNPACKED, "mw_quiz_data.nss")
ENGINE_NSS = os.path.join(UNPACKED, "mw_quiz_inc.nss")
MD_PATH = os.path.join(REPO, "MeaningWave.md")

NO_DELAY = 4294967295

# Guide order (matches mw_unlock_inc MW_GuideAt for the roster) and the target
# NWScript row-function name for each. These are game-side details kept out of the
# YAML so the bank file stays clean for the wiki.
GUIDE_ORDER = ["jocko", "peterson", "watts", "campbell", "mckenna", "jung", "aurelius"]
FUNC = {"jocko": "MW_JocRow", "peterson": "MW_PetRow", "watts": "MW_WatRow",
        "campbell": "MW_CamRow", "mckenna": "MW_MckRow", "jung": "MW_JunRow",
        "aurelius": "MW_AurRow"}

RESERVED = ("~", "|", "\n", "\r", "\t")   # '~' packs rows, '|' reserved; no newlines
BANK_SIZE = 20

# Per-guide flavour text for the dialogue templates (not part of the question bank).
GUIDES = {
    "peterson": {
        "intro": "Stand up straight, with your shoulders back. You came here because something in the music drew you. Good. Now — are you willing to be tested? Or will you flinch back into chaos?",
        "begin": "Test me.",
        "decline": "Not today.",
        "decline_entry": "Then sort yourself out first, and come back when you are ready.",
        "pass": "Good. You can bear weight. When you next dream, I will walk beside you. Make your bed. Tell the truth. Pursue what is meaningful, not what is expedient.",
        "fail": "You stumble. Set your house in order. Take on more weight than you think you can carry. Then come back to me.",
        "unlocked": "You have already sorted yourself out, <FullName>. You carry the right answers. There is no quiz for those who have already faced themselves.",
        "term_pass": "Thank you, sir.",
        "term_fail": "I will return.",
        "term_unlk": "Thank you, sir.",
    },
    "watts": {
        "intro": "Welcome, dear friend. You are the universe playing hide-and-seek with itself. Shall we play a small game of questions, or will you wander on?",
        "begin": "Ask. I will answer.",
        "decline": "Not today.",
        "decline_entry": "Then walk on.",
        "pass": "Hahaha. You see it now. When you next dream, I will be there to laugh with you.",
        "fail": "Oh dear, you are still pretending to be a separate thing. Wander a while; the joke will land when it lands.",
        "unlocked": "Ha. The river does not need to remember flowing, <FullName>. You have already understood what most spend a lifetime avoiding. Come back to laugh with me — but there is nothing left to prove.",
        "term_pass": "Thank you.",
        "term_fail": "I will return.",
        "term_unlk": "Of course. Thank you.",
    },
    "campbell": {
        "intro": "Hello, traveller. Every hero's tale is yours, and every name you read is your own. Will you let me test what you remember of the path?",
        "begin": "Ask. I will answer.",
        "decline": "Not today.",
        "decline_entry": "Then walk on.",
        "pass": "You walk the path. Follow your bliss — and when you dream, I will be your companion at the threshold.",
        "fail": "You have not yet heard the call. Listen. The world is full of calls.",
        "unlocked": "You have already heard the call and answered it, <FullName>. Your bliss is already leading you forward. The threshold is behind you — walk on.",
        "term_pass": "Thank you.",
        "term_fail": "I will return.",
        "term_unlk": "Thank you.",
    },
    "mckenna": {
        "intro": "Well, well. Another monkey wandering between dimensions. Sit. I want to ask you a few things about the felt presence of immediate experience.",
        "begin": "Ask. I will answer.",
        "decline": "Not today.",
        "decline_entry": "Then walk on.",
        "pass": "Beautiful. The next time you sleep, I will meet you in the dream. Bring the dose.",
        "fail": "You are still living in the syntactic prison. Eat something strange and try again.",
        "unlocked": "You're already running the new software, <FullName>. Your operating system has been updated. The Other has recognized you. Come back any time to compare notes.",
        "term_pass": "Thank you.",
        "term_fail": "I will return.",
        "term_unlk": "Thank you.",
    },
    "jocko": {
        "intro": "You. I am running a small inventory of who is and is not built for this. Five questions. Stand up straight. Answer.",
        "begin": "Ask. I will answer.",
        "decline": "Not today.",
        "decline_entry": "Then walk on.",
        "pass": "GOOD. When you rest, I will march with you. Get after it.",
        "fail": "You are not ready. Train. Come back.",
        "unlocked": "You already showed up. Test over. GOOD.",
        "term_pass": "Thank you.",
        "term_fail": "I will return.",
        "term_unlk": "Thank you.",
    },
    "jung": {
        "intro": "Step closer to the mirror. I will not bite. I am only asking that you look at what stands behind you. Will you answer some questions about it?",
        "begin": "Ask. I will answer.",
        "decline": "Not today.",
        "decline_entry": "Then walk on.",
        "pass": "Then come into the mirror with me. When you next dream, I will help you read it.",
        "fail": "Your shadow stands behind you, unread. Look again.",
        "unlocked": "You have already looked into the mirror without flinching, <FullName>. The shadow is known to you. Return whenever the unconscious speaks — I will be here.",
        "term_pass": "Thank you.",
        "term_fail": "I will return.",
        "term_unlk": "Thank you.",
    },
    "aurelius": {
        "intro": "Sit, citizen. The throne is comfortable enough. Five questions on the things in your power and the things not. Answer plainly.",
        "begin": "Ask. I will answer.",
        "decline": "Not today.",
        "decline_entry": "Then walk on.",
        "pass": "Acceptable. When you sleep, I will read with you. Memento mori.",
        "fail": "You confuse what is yours with what is the world's. Sit longer with that.",
        "unlocked": "You remember what is in your power, and you act on it, <FullName>. Memento mori. The work continues — but the test is done.",
        "term_pass": "Thank you.",
        "term_fail": "I will return.",
        "term_unlk": "Memento mori.",
    },
}

NUM_QUESTIONS = 5   # question slots in each dialogue (must equal meta.draw)
NUM_OPTS = 4        # answer choices per question (must equal meta.options)


# ---- load + validate the canonical bank -----------------------------------

def load_bank():
    with open(BANK_YAML, encoding="utf-8") as f:
        return yaml.safe_load(f)


def engine_constants():
    """Read MW_QUIZ_DRAW/PASS/OPTS from the runtime engine so meta can't drift."""
    src = open(ENGINE_NSS, encoding="utf-8").read()
    out = {}
    for name in ("DRAW", "PASS", "OPTS"):
        m = re.search(r"const int MW_QUIZ_%s\s*=\s*(\d+)\s*;" % name, src)
        if not m:
            raise SystemExit("could not find MW_QUIZ_%s in %s" % (name, ENGINE_NSS))
        out[name.lower()] = int(m.group(1))
    return out


def validate(bank):
    errs = []
    meta = bank.get("meta", {})
    eng = engine_constants()
    for k, ename in (("draw", "draw"), ("pass", "pass"), ("options", "opts")):
        if meta.get(k) != eng[ename]:
            errs.append("meta.%s=%r != engine MW_QUIZ_%s=%r"
                        % (k, meta.get(k), ename.upper(), eng[ename]))

    guides = bank.get("guides", {})
    if set(guides) != set(GUIDE_ORDER):
        errs.append("guides %s != expected %s" % (sorted(guides), sorted(GUIDE_ORDER)))

    for key in GUIDE_ORDER:
        g = guides.get(key)
        if not g:
            continue
        for field in ("display_name", "tested_on"):
            if not str(g.get(field, "")).strip():
                errs.append("%s: missing %s" % (key, field))
        qs = g.get("questions", [])
        if len(qs) != BANK_SIZE:
            errs.append("%s: %d questions (want %d)" % (key, len(qs), BANK_SIZE))
        for i, q in enumerate(qs):
            opts = [q.get("q", ""), q.get("correct", "")] + list(q.get("distractors", []))
            if len(q.get("distractors", [])) != NUM_OPTS - 1:
                errs.append("%s[%d]: %d distractors (want %d)"
                            % (key, i, len(q.get("distractors", [])), NUM_OPTS - 1))
            for f in opts:
                if not str(f).strip():
                    errs.append("%s[%d]: empty field" % (key, i)); break
            for f in opts:
                for c in RESERVED:
                    if c in str(f):
                        errs.append("%s[%d]: reserved char %r in %r" % (key, i, c, f))
                try:
                    str(f).encode("ascii")
                except UnicodeEncodeError:
                    errs.append("%s[%d]: non-ASCII in %r (breaks nss compile)" % (key, i, f))
            answers = [q.get("correct", "")] + list(q.get("distractors", []))
            if len(set(answers)) != len(answers):
                errs.append("%s[%d]: options not distinct: %s" % (key, i, answers))
    if errs:
        raise SystemExit("mw_quiz_bank.yaml INVALID:\n  - " + "\n  - ".join(errs))


# ---- artifact builders -----------------------------------------------------

def nss_escape(s):
    """Escape a bank field for an NWScript string literal (supports \\\\ and \\")."""
    return str(s).replace("\\", "\\\\").replace('"', '\\"')


def build_nss(bank):
    guides = bank["guides"]
    L = []
    L.append("//::///////////////////////////////////////////////")
    L.append("//:: mw_quiz_data -- MeaningWave guide quiz question banks.")
    L.append("//::")
    L.append("//:: GENERATED from mw_quiz_bank.yaml by bin/gen-mw-quiz.py -- DO NOT EDIT.")
    L.append("//:: Edit the YAML and re-run the generator (tests/check_mw_quiz.py gates it).")
    L.append("//::")
    L.append("//:: Each question is one packed row consumed by mw_quiz_inc:")
    L.append("//::     \"QUESTION~RIGHT~WRONG1~WRONG2~WRONG3\"")
    L.append("//:: Field 0 is the prompt, field 1 the single correct answer, 2-4 distractors.")
    L.append("//:://////////////////////////////////////////////")
    L.append("")
    L.append("const int MW_BANK_SIZE = %d;" % BANK_SIZE)
    L.append("")
    L.append("int MW_QCount(string sGuide) { return MW_BANK_SIZE; }")
    L.append("")
    for key in GUIDE_ORDER:
        g = guides[key]
        L.append("// %s -- %s" % (g["display_name"], g["tested_on"]))
        L.append("string %s(int i)" % FUNC[key])
        L.append("{")
        L.append("    switch (i)")
        L.append("    {")
        for i, q in enumerate(g["questions"]):
            row = "~".join([q["q"], q["correct"]] + list(q["distractors"]))
            L.append('        case %-2d: return "%s";' % (i, nss_escape(row)))
        L.append("    }")
        L.append("    return \"\";")
        L.append("}")
        L.append("")
    L.append("// Dispatch: packed row for guide sGuide, question index i (0-based).")
    L.append("string MW_QRow(string sGuide, int i)")
    L.append("{")
    for key in GUIDE_ORDER:
        L.append('    if (sGuide == "%s")%s return %s(i);'
                 % (key, " " * (9 - len(key)), FUNC[key]))
    L.append("    return \"\";")
    L.append("}")
    return "\n".join(L) + "\n"


def build_json(bank):
    guides = {}
    for key in GUIDE_ORDER:
        g = bank["guides"][key]
        guides[key] = {
            "display_name": g["display_name"],
            "tested_on": g["tested_on"],
            "questions": [
                {"q": q["q"], "correct": q["correct"],
                 "distractors": list(q["distractors"])}
                for q in g["questions"]
            ],
        }
    doc = {"meta": bank["meta"], "guides": guides}
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


MD_HEADER = "## Quiz question banks (answer key)"
MD_NEXT = "## How the quiz engine works"


def build_md_section(bank):
    L = []
    L.append(MD_HEADER)
    L.append("")
    L.append("**Generated from `mw_quiz_bank.yaml` by `bin/gen-mw-quiz.py` — do not edit here.**")
    L.append("The YAML bank is the single source of truth; the same generator also emits")
    L.append("`mw_quiz_bank.json` (the browser-native twin a wiki quiz engine can read) and")
    L.append("`unpacked/mw_quiz_data.nss` (the compiled-in bank the game uses), so all three stay")
    L.append("in sync. To change a question, edit the YAML, run `python3 bin/gen-mw-quiz.py`, then")
    L.append("`python3 tests/check_mw_quiz.py`.")
    L.append("")
    L.append("Each run draws **5 of a guide's 20 at random** and shuffles the four options, so the")
    L.append("correct answer is never in a fixed slot. The **bold** answer is correct; the rest are")
    L.append("distractors. The `[guide NN]` tag is the bank index (its position in the YAML).")
    for key in GUIDE_ORDER:
        g = bank["guides"][key]
        L.append("")
        L.append("### %s — `%s`" % (g["display_name"], FUNC[key]))
        L.append("")
        L.append("_Tested on: %s._" % g["tested_on"])
        L.append("")
        for i, q in enumerate(g["questions"]):
            d = q["distractors"]
            L.append("- **[%s %02d]** %s → **%s** _(distractors: %s · %s · %s)_"
                     % (key, i, q["q"], q["correct"], d[0], d[1], d[2]))
    return "\n".join(L) + "\n\n"


def render_md(bank):
    md = open(MD_PATH, encoding="utf-8").read()
    start = md.index(MD_HEADER)
    end = md.index(MD_NEXT)
    return md[:start] + build_md_section(bank) + md[end:]


# ---- dialogue templates (unchanged) ---------------------------------------

def dword(v):  return {"type": "dword", "value": v}
def byte(v):   return {"type": "byte", "value": v}
def resref(v): return {"type": "resref", "value": v}
def cexo(v):   return {"type": "cexostring", "value": v}
def loc(v):    return {"type": "cexolocstring", "value": {"0": v}}


def link(struct_id, index, active=""):
    return {"__struct_id": struct_id, "Active": resref(active),
            "Index": dword(index), "IsChild": byte(0)}


def entry(struct_id, text, script, replies):
    return {
        "__struct_id": struct_id,
        "Animation": dword(0), "AnimLoop": byte(1),
        "Comment": cexo(""), "Delay": dword(NO_DELAY), "Quest": cexo(""),
        "RepliesList": {"type": "list",
                        "value": [link(i, idx, act) for i, (idx, act) in enumerate(replies)]},
        "Script": resref(script), "Sound": resref(""), "Speaker": cexo(""),
        "Text": loc(text),
    }


def reply(struct_id, text, script, entries):
    return {
        "__struct_id": struct_id,
        "Animation": dword(0), "AnimLoop": byte(1),
        "Comment": cexo(""), "Delay": dword(NO_DELAY),
        "EntriesList": {"type": "list",
                        "value": [link(i, idx, act) for i, (idx, act) in enumerate(entries)]},
        "Quest": cexo(""), "Script": resref(script), "Sound": resref(""),
        "Text": loc(text),
    }


def build_dlg(flavour):
    E_INTRO, E_Q1, E_PASS, E_FAIL, E_DECLINE, E_UNLK = 0, 1, 6, 7, 8, 9
    R_BEGIN, R_DECLINE = 0, 1
    R_ANS0 = 2
    R_TERM_PASS = R_ANS0 + NUM_QUESTIONS * NUM_OPTS
    R_TERM_FAIL = R_TERM_PASS + 1
    R_TERM_UNLK = R_TERM_PASS + 2

    entries = []
    entries.append(entry(E_INTRO, flavour["intro"], "mw_q_enc",
                         [(R_BEGIN, ""), (R_DECLINE, "")]))
    for q in range(NUM_QUESTIONS):
        base = R_ANS0 + q * NUM_OPTS
        entries.append(entry(E_Q1 + q, "<CUSTOM7005>\n\n<CUSTOM7000>", "mw_q_load",
                             [(base + s, "") for s in range(NUM_OPTS)]))
    entries.append(entry(E_PASS, flavour["pass"], "mw_q_unlock", [(R_TERM_PASS, "")]))
    entries.append(entry(E_FAIL, flavour["fail"], "", [(R_TERM_FAIL, "")]))
    entries.append(entry(E_DECLINE, flavour["decline_entry"], "", []))
    entries.append(entry(E_UNLK, flavour["unlocked"], "", [(R_TERM_UNLK, "")]))

    replies = []
    replies.append(reply(R_BEGIN, flavour["begin"], "mw_q_start", [(E_Q1, "")]))
    replies.append(reply(R_DECLINE, flavour["decline"], "", [(E_DECLINE, "")]))
    for q in range(NUM_QUESTIONS):
        for s in range(NUM_OPTS):
            ridx = R_ANS0 + q * NUM_OPTS + s
            if q < NUM_QUESTIONS - 1:
                dest = [(E_Q1 + q + 1, "")]
            else:
                dest = [(E_PASS, "mw_q_pass"), (E_FAIL, "")]
            replies.append(reply(ridx, "<CUSTOM700%d>" % (s + 1),
                                 "mw_q_a%d" % (s + 1), dest))
    replies.append(reply(R_TERM_PASS, flavour["term_pass"], "", []))
    replies.append(reply(R_TERM_FAIL, flavour["term_fail"], "", []))
    replies.append(reply(R_TERM_UNLK, flavour["term_unlk"], "", []))

    starting = {"type": "list", "value": [
        {"__struct_id": 0, "Active": resref("mw_q_chk"), "Index": dword(E_UNLK)},
        {"__struct_id": 1, "Active": resref(""), "Index": dword(E_INTRO)},
    ]}
    return {
        "__data_type": "DLG ",
        "DelayEntry": dword(0), "DelayReply": dword(0),
        "EndConverAbort": resref(""), "EndConversation": resref(""),
        "EntryList": {"type": "list", "value": entries},
        "NumWords": dword(0), "PreventZoomIn": byte(0),
        "ReplyList": {"type": "list", "value": replies},
        "StartingList": starting,
    }


# ---- driver ----------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify on-disk artifacts match the YAML (exit 1 if not)")
    args = ap.parse_args()

    bank = load_bank()
    validate(bank)

    # (path, generated text) for the text artifacts
    artifacts = [
        (BANK_JSON, build_json(bank)),
        (DATA_NSS, build_nss(bank)),
        (MD_PATH, render_md(bank)),
    ]
    for guide, flavour in GUIDES.items():
        path = os.path.join(UNPACKED, "mw_%s_m.dlg.json" % guide)
        artifacts.append((path, json.dumps(build_dlg(flavour), indent=2,
                                           ensure_ascii=False) + "\n"))

    if args.check:
        stale = []
        for path, text in artifacts:
            on_disk = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if on_disk != text:
                stale.append(os.path.relpath(path, REPO))
        if stale:
            print("OUT OF DATE (run: python3 bin/gen-mw-quiz.py):", file=sys.stderr)
            for p in stale:
                print("  - %s" % p, file=sys.stderr)
            sys.exit(1)
        print("OK: bank JSON, mw_quiz_data.nss, MeaningWave.md, and 7 dialogues in sync.")
        return

    for path, text in artifacts:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print("wrote %s" % os.path.relpath(path, REPO))


if __name__ == "__main__":
    main()
