#!/usr/bin/env python3
"""MeaningWave quiz bank integrity check (build-time smoke test).

Each of the seven guides has a 20-question bank in unpacked/mw_quiz_data.nss. The
quiz engine (mw_quiz_inc) draws 5 at random and shuffles the four choices, so the
banks must be well-formed or a run could show a blank/duplicate option or crash
the picker. This gate enforces, for every guide:

  * exactly 20 question rows (indices 0..19, no gaps or dupes);
  * every packed row splits into exactly 5 '~'-delimited fields
    (prompt, correct, wrong1, wrong2, wrong3), all non-empty;
  * the three distractors are distinct from each other and from the correct
    answer (so there is a single unambiguous right choice).

It also checks:
  * the generated dialogues are up to date (bin/gen-mw-quiz.py --check), and
  * the human-readable answer key in MeaningWave.md lists 20 questions per guide,
    matching the .nss banks count-for-count.

Scans the repo directly. Exits 0 on success, 1 on any failure.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")
DATA = os.path.join(UNPACKED, "mw_quiz_data.nss")
MDOC = os.path.join(ROOT, "MeaningWave.md")

GUIDES = ["jocko", "peterson", "watts", "campbell", "mckenna", "jung", "aurelius"]
FUNC = {  # guide -> its row function name in mw_quiz_data.nss
    "jocko": "MW_JocRow", "peterson": "MW_PetRow", "watts": "MW_WatRow",
    "campbell": "MW_CamRow", "mckenna": "MW_MckRow", "jung": "MW_JunRow",
    "aurelius": "MW_AurRow",
}
BANK_SIZE = 20
FIELDS = 5  # prompt + correct + 3 distractors

CASE_RE = re.compile(r'case\s+(\d+):\s*return\s+"((?:[^"\\]|\\.)*)"\s*;')


def parse_bank(src, func):
    """Return {index: [fields]} for one guide's row function."""
    m = re.search(r'string\s+%s\s*\(int\s+i\)\s*\{(.*?)\n\}' % re.escape(func),
                  src, re.DOTALL)
    if not m:
        return None
    rows = {}
    for cm in CASE_RE.finditer(m.group(1)):
        idx = int(cm.group(1))
        raw = cm.group(2).encode().decode("unicode_escape")
        rows[idx] = raw.split("~")
    return rows


def main():
    errs = []

    if not os.path.exists(DATA):
        print("fail: %s missing" % os.path.relpath(DATA, ROOT))
        return 1
    src = open(DATA, encoding="utf-8").read()

    for g in GUIDES:
        rows = parse_bank(src, FUNC[g])
        if rows is None:
            errs.append("%s: function %s not found" % (g, FUNC[g]))
            continue
        idxs = sorted(rows)
        if idxs != list(range(BANK_SIZE)):
            errs.append("%s: indices %s (want 0..%d)" % (g, idxs, BANK_SIZE - 1))
        for i, fields in rows.items():
            if len(fields) != FIELDS:
                errs.append("%s[%d]: %d fields, want %d" % (g, i, len(fields), FIELDS))
                continue
            if any(not f.strip() for f in fields):
                errs.append("%s[%d]: has an empty field" % (g, i))
            answers = fields[1:]
            if len(set(answers)) != len(answers):
                errs.append("%s[%d]: duplicate answer options: %s" % (g, i, answers))

    # Generated dialogues up to date?
    gen = subprocess.run([sys.executable, os.path.join(ROOT, "bin", "gen-mw-quiz.py"),
                          "--check"], capture_output=True, text=True)
    if gen.returncode != 0:
        errs.append("generated dialogues out of date: %s" %
                    (gen.stdout + gen.stderr).strip())

    # MeaningWave.md answer key present and 20 per guide?
    if not os.path.exists(MDOC):
        errs.append("MeaningWave.md missing")
    else:
        md = open(MDOC, encoding="utf-8").read()
        for g in GUIDES:
            # Count answer-key rows tagged for this guide, e.g. "[jocko 03]".
            n = len(re.findall(r'\[%s\s+\d+\]' % g, md))
            if n != BANK_SIZE:
                errs.append("MeaningWave.md: %s answer key has %d rows, want %d"
                            % (g, n, BANK_SIZE))

    if errs:
        print("MeaningWave quiz check FAILED:")
        for e in errs:
            print("  - %s" % e)
        return 1
    print("MeaningWave quiz check OK: 7 guides x %d questions, dialogues + doc in sync."
          % BANK_SIZE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
