#!/usr/bin/env python3
"""Build gate: behaviour flags must match this environment's SEASON_ROLE.

Cheat gear, the Ping Pong builder NPC and the early-access wipe notice are ON in
a dev or early-access realm and OFF in production. They are not authored in the
tree - they are generated into unpacked/season_prof_inc.nss from SEASON_ROLE
by bin/season-profile.py, because dev and production share one source tree and
bin/season-promote.sh overwrites production's copy with dev's on every release.
A hand-edited flag would therefore be reverted by the next successful deploy.

This gate is the safety net for that whole design. It fails the repack when:

  - season_prof_inc.nss is out of date with SEASON_ROLE (e.g. the role was
    flipped to `live` but the flags were never regenerated), or
  - a consumer stopped reading its flag and went back to a literal, which would
    opt that behaviour out of the mechanism entirely while everything still
    looked correct.

Without it, "production got its cheats turned off" is something a human has to
remember at every cutover. The cutover guide is largely a record of what
happens to things humans have to remember.

Exit 0 = in sync, 1 = drifted (or the script errored).
"""
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROFILE = REPO / "bin" / "season-profile.py"


def main() -> int:
    if not PROFILE.exists():
        print(f"FAIL season-profile: {PROFILE} is missing")
        return 1

    proc = subprocess.run(
        [sys.executable, str(PROFILE), "--check"],
        capture_output=True, text=True, cwd=str(REPO),
    )
    out = (proc.stdout + proc.stderr).strip()

    if proc.returncode == 0:
        # First line carries role + the resolved flags. Worth showing: a repack
        # that quietly built the wrong profile is otherwise invisible in the log,
        # and "cheat_chest=on" in a live season's build output is the single most
        # useful thing this gate can print.
        first = out.splitlines()[0] if out else ""
        print(f"ok season-profile: {first}")
        return 0

    print("FAIL season-profile: behaviour flags do not match SEASON_ROLE")
    for line in out.splitlines():
        print(f"       {line}")
    print("       fix: python3 bin/season-profile.py --apply")
    return 1


if __name__ == "__main__":
    sys.exit(main())
