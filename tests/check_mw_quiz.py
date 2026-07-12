#!/usr/bin/env python3
"""MeaningWave quiz bank integrity check (build-time smoke test).

`mw_quiz_bank.yaml` (repo root) is the single source of truth for the seven guides'
20-question banks. bin/gen-mw-quiz.py derives the game bank (unpacked/mw_quiz_data.nss),
the wiki twin (mw_quiz_bank.json), the MeaningWave.md answer key, and the seven quiz
dialogues from it. The quiz engine draws 5 questions at random and shuffles the four
choices, so a malformed bank could show a blank/duplicate option or crash the picker.

This gate:
  * schema-validates mw_quiz_bank.yaml via the generator's own validate() (exactly 20
    questions/guide; non-empty prompt + correct + 3 distractors; 4 distinct options;
    ASCII only; no '~'/'|'/newline; meta matches the mw_quiz_inc engine constants), and
  * runs `gen-mw-quiz.py --check` so a stale .nss, .json, MeaningWave.md, or dialogue
    (i.e. someone edited a derived file, or edited the YAML without regenerating) fails
    the build.

Exits 0 on success, 1 on any failure.
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "bin", "gen-mw-quiz.py")
BANK = os.path.join(ROOT, "mw_quiz_bank.yaml")


def main():
    if not os.path.exists(BANK):
        print("MeaningWave quiz check FAILED: mw_quiz_bank.yaml missing")
        return 1

    # validate() runs first inside the generator; --check then diffs every artifact.
    proc = subprocess.run([sys.executable, GEN, "--check"],
                          capture_output=True, text=True)
    out = (proc.stdout + proc.stderr).strip()
    if proc.returncode != 0:
        print("MeaningWave quiz check FAILED:")
        for line in out.splitlines():
            print("  " + line)
        return 1

    print("MeaningWave quiz check OK: bank valid; nss/json/doc/dialogues in sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
