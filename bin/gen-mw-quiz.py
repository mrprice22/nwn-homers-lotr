#!/usr/bin/env python3
"""Generate the MeaningWave guide quiz conversations (mw_<guide>_m.dlg.json).

Every guide's quiz is structurally identical -- an intro, five *dynamic* question
slots (each loaded at runtime by mw_q_load, showing tokens 7000/7001-7004/7005),
and pass/fail/decline/already-unlocked branches -- differing only in the guide's
flavour text and the guide name derived from the NPC tag. Rather than hand-edit
seven near-identical GFF-JSON trees (which risks the link-only-field corruption
that makes the engine silently refuse to load a conversation), we emit them from
one template here.

The actual questions/answers live in unpacked/mw_quiz_data.nss and are injected at
runtime via custom tokens -- they are NOT in these dialogue files.

Usage:
    python3 bin/gen-mw-quiz.py            # write the 7 dlg files
    python3 bin/gen-mw-quiz.py --check    # verify on-disk files match (CI gate)
"""
import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(REPO, "unpacked")

NO_DELAY = 4294967295

# Per-guide flavour text. Structure/scripts/tokens are shared across all guides.
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

NUM_QUESTIONS = 5
NUM_OPTS = 4

# ---- GFF-JSON builders -----------------------------------------------------

def dword(v):     return {"type": "dword", "value": v}
def byte(v):      return {"type": "byte", "value": v}
def resref(v):    return {"type": "resref", "value": v}
def cexo(v):      return {"type": "cexostring", "value": v}
def loc(v):       return {"type": "cexolocstring", "value": {"0": v}}

def link(struct_id, index, active=""):
    return {"__struct_id": struct_id, "Active": resref(active),
            "Index": dword(index), "IsChild": byte(0)}

def entry(struct_id, text, script, replies):
    """replies = list of (reply_index, active) links, in display order."""
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
    """entries = list of (entry_index, active) links, in evaluation order."""
    return {
        "__struct_id": struct_id,
        "Animation": dword(0), "AnimLoop": byte(1),
        "Comment": cexo(""), "Delay": dword(NO_DELAY),
        "EntriesList": {"type": "list",
                        "value": [link(i, idx, act) for i, (idx, act) in enumerate(entries)]},
        "Quest": cexo(""), "Script": resref(script), "Sound": resref(""),
        "Text": loc(text),
    }


def build(flavour):
    # Entry layout: 0 intro, 1..5 questions, 6 pass, 7 fail, 8 decline, 9 unlocked
    E_INTRO, E_Q1, E_PASS, E_FAIL, E_DECLINE, E_UNLK = 0, 1, 6, 7, 8, 9

    # Reply layout: 0 begin, 1 decline, 2.. answers (5*4), then 3 terminals
    R_BEGIN, R_DECLINE = 0, 1
    R_ANS0 = 2
    R_TERM_PASS = R_ANS0 + NUM_QUESTIONS * NUM_OPTS       # 22
    R_TERM_FAIL = R_TERM_PASS + 1                         # 23
    R_TERM_UNLK = R_TERM_PASS + 2                         # 24

    # --- entries ---
    entries = []
    entries.append(entry(E_INTRO, flavour["intro"], "mw_q_enc",
                         [(R_BEGIN, ""), (R_DECLINE, "")]))
    for q in range(NUM_QUESTIONS):
        eidx = E_Q1 + q
        base = R_ANS0 + q * NUM_OPTS
        entries.append(entry(eidx, "<CUSTOM7005>\n\n<CUSTOM7000>", "mw_q_load",
                             [(base + s, "") for s in range(NUM_OPTS)]))
    entries.append(entry(E_PASS, flavour["pass"], "mw_q_unlock", [(R_TERM_PASS, "")]))
    entries.append(entry(E_FAIL, flavour["fail"], "", [(R_TERM_FAIL, "")]))
    entries.append(entry(E_DECLINE, flavour["decline_entry"], "", []))
    entries.append(entry(E_UNLK, flavour["unlocked"], "", [(R_TERM_UNLK, "")]))

    # --- replies ---
    replies = []
    replies.append(reply(R_BEGIN, flavour["begin"], "mw_q_start", [(E_Q1, "")]))
    replies.append(reply(R_DECLINE, flavour["decline"], "", [(E_DECLINE, "")]))
    for q in range(NUM_QUESTIONS):
        for s in range(NUM_OPTS):
            ridx = R_ANS0 + q * NUM_OPTS + s
            if q < NUM_QUESTIONS - 1:
                dest = [(E_Q1 + q + 1, "")]              # -> next question
            else:
                dest = [(E_PASS, "mw_q_pass"), (E_FAIL, "")]  # final -> pass/fail
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify on-disk files match generated output (exit 1 if not)")
    args = ap.parse_args()

    mismatch = False
    for guide, flavour in GUIDES.items():
        path = os.path.join(UNPACKED, "mw_%s_m.dlg.json" % guide)
        text = json.dumps(build(flavour), indent=2, ensure_ascii=False) + "\n"
        if args.check:
            on_disk = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if on_disk != text:
                print("OUT OF DATE: %s" % os.path.relpath(path, REPO))
                mismatch = True
        else:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            print("wrote %s" % os.path.relpath(path, REPO))

    if args.check and mismatch:
        print("Run: python3 bin/gen-mw-quiz.py", file=sys.stderr)
        sys.exit(1)
    if args.check:
        print("OK: all 7 quiz dialogues up to date.")


if __name__ == "__main__":
    main()
