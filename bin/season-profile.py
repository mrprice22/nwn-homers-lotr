#!/usr/bin/env python3
"""Derive this environment's BEHAVIOUR flags from its season block.

`bin/season-brand.py` owns strings and URLs. This script owns *flags*: the
handful of things that must be ON in a dev or early-access realm and OFF in
production — cheat gear, the dev builder NPC, the early-access wipe notice.

## Why this exists

Before the permanent dev realm, "production has no cheat gear" was a hand edit
to module source: you set `DON_CHEAT_ENABLED = FALSE` in don_cheat_inc.nss and
repacked, once, at the cutover. That works exactly once, for an environment that
is *becoming* production and never syncs again.

It does not survive a dev realm. Dev and production now share one source tree,
and bin/season-promote.sh copies dev's tree into production on every release —
so a hand-edited FALSE in production is overwritten by dev's TRUE the first time
anyone ships a change, and the live season quietly starts handing out
best-in-slot gear. The failure is silent, and it happens on a *successful*
deploy.

So the flags cannot live in the tree as authored values. They are generated from
`SEASON_ROLE`, the two trees stay byte-identical, and the environment decides.

## The contract

    unpacked/season_prof_inc.nss   is GENERATED. Never hand-edit it.
    every consumer reads an SP_* constant, never a literal.

`--check` enforces both halves and is wired into the repack build gate via
tests/check_season_profile.py, so a repo with SEASON_ROLE=live and cheats on
cannot be packed. That gate is the whole safety net for the promotion design:
without it, "did production get rebranded correctly?" is a thing you have to
remember, and the guide is full of evidence about what happens to those.

Usage:
    python3 bin/season-profile.py              # dry run — show what would change
    python3 bin/season-profile.py --apply      # write
    python3 bin/season-profile.py --check      # exit 1 if out of date (build gate)
    python3 bin/season-profile.py --diff       # dry run with full unified diffs

IDEMPOTENCE is the contract, as in season-brand.py: a second --apply produces no
diff. Trivially true here because the generated file is a pure function of the
role.
"""
from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"
GENERATED = UNPACKED / "season_prof_inc.nss"


class ProfileError(Exception):
    pass


# --- the flag matrix --------------------------------------------------------
# One row per role. Keep this table as the ONLY place a role/flag pair is
# decided; everything downstream reads the constants.
#
#   SP_DEV_TOOLS    the Ping Pong builder NPC (tag BUTCHA) and its set-level /
#                   set-gold scripts. A player-facing feature must never be
#                   gated on this — see the legendary-feat re-pick note in
#                   README.md "Re-choosing legendary feats".
#   SP_CHEAT_CHEST  the Donations Chest best-in-slot restock (don_cheat_inc).
#   SP_WIPE_NOTICE  the cyan early-access "everything here is wiped" login
#                   block in servershout4.nss.
FLAGS = ("SP_DEV_TOOLS", "SP_CHEAT_CHEST", "SP_WIPE_NOTICE")

PROFILE: dict[str, dict[str, bool]] = {
    # dev: permanent test realm, password-gated, never public progress.
    "dev":     {"SP_DEV_TOOLS": True,  "SP_CHEAT_CHEST": True,  "SP_WIPE_NOTICE": False},
    # test: early-access realm. Same tools as dev, plus the wipe warning,
    # because its players are real players whose progress really is temporary.
    "test":    {"SP_DEV_TOOLS": True,  "SP_CHEAT_CHEST": True,  "SP_WIPE_NOTICE": True},
    # live: production. Everything off. This row is the one that matters.
    "live":    {"SP_DEV_TOOLS": False, "SP_CHEAT_CHEST": False, "SP_WIPE_NOTICE": False},
    # archive: a retired season, still playable. Progress is real (it was a
    # live season), so no wipe notice and no cheats.
    "archive": {"SP_DEV_TOOLS": False, "SP_CHEAT_CHEST": False, "SP_WIPE_NOTICE": False},
}

# --- wiring checks ----------------------------------------------------------
# Generating the include is only half the job: a consumer that goes back to a
# literal silently opts out of the whole mechanism, and --check would still
# pass. Each entry asserts the consumer still reads the constant.
#
# These are deliberately shape-loose (the constant name, not a full line) so
# ordinary edits to the surrounding code don't trip them, and deliberately
# fatal, because the thing they protect against is exactly the edit that looks
# harmless in review.
#
# The second element may be a TUPLE of acceptable symbols, for a consumer that
# legitimately reads the flag through a shared helper rather than directly. That
# is not a loophole: the helper itself is listed here too, so the flag is still
# checked at every hop, and a consumer that drops its guard entirely still
# fails. sp_devgate_inc.nss exists because the two Ping Pong consumers MUST
# agree - when they disagreed, the conversation gate admitted an admin on a live
# season and the level setter then refused them in silence.
WIRING: list[tuple[str, str | tuple[str, ...], str]] = [
    ("don_cheat_inc.nss", "SP_CHEAT_CHEST",
     "the Donations Chest cheat stock must read SP_CHEAT_CHEST, not a literal"),
    ("servershout4.nss", "SP_WIPE_NOTICE",
     "the early-access login block must be guarded by SP_WIPE_NOTICE"),
    ("_build_lvl_inc.nss", ("SP_DEV_TOOLS", "SP_DevToolsFor"),
     "the PC-builder level setter must be guarded by SP_DEV_TOOLS, directly or "
     "through SP_DevToolsFor"),
    ("onmoduleload.nss", "SP_DEV_TOOLS",
     "the module load script must run the dev-tool purge"),
    ("sp_devgate.nss", ("SP_DEV_TOOLS", "SP_DevToolsFor"),
     "the dev-tool conversation gate must read SP_DEV_TOOLS, directly or "
     "through SP_DevToolsFor - this is the guard that holds when the "
     "module-load purge does not, as it did not at the season 2 launch "
     "(DestroyObject refuses a Plot creature)"),
    ("sp_devgate_inc.nss", "SP_DEV_TOOLS",
     "the shared dev-tool predicate is where both Ping Pong consumers now read "
     "the flag - if it stops reading SP_DEV_TOOLS, both of them silently open"),
]


def load_env(path: Path) -> dict[str, str]:
    """Parse KEY=VALUE lines, matching bash's trailing-comment handling.

    Deliberately a copy of season-brand.py's parser rather than an import:
    these two scripts are copied between repos by the promote script and each
    has to stand alone. The duplication is three lines of regex and has never
    drifted; a shared module would be a fourth file to keep in sync.
    """
    env: dict[str, str] = {}
    if not path.exists():
        raise ProfileError(f"missing {path}")
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$", line)
        if not m:
            continue
        key, rest = m.group(1), m.group(2)
        q = rest[:1]
        if q in ('"', "'"):
            end = rest.find(q, 1)
            val = rest[1:end] if end > 0 else rest[1:]
        else:
            val = re.split(r"\s+#", rest, maxsplit=1)[0].strip()
        env[key] = val
    return env


def render(role: str) -> str:
    flags = PROFILE[role]
    width = max(len(f) for f in FLAGS)
    # ASCII ONLY. NWN reads script text as windows-1252, so a UTF-8 em dash is
    # three bytes to the game and is a known compile trap even in a comment --
    # see bin/ascii-clean-nss.py and tests/check_ascii_nss.py, which gates it.
    # A generator that emits one would fail that gate on every repo it writes.
    lines = [
        "// GENERATED by bin/season-profile.py from SEASON_ROLE in server.env.",
        "// DO NOT EDIT - `season-profile.py --check` is a repack build gate, so a",
        "// hand edit here fails the next build rather than shipping.",
        "//",
        f"// This environment's role: {role}",
        "//",
        "// Flip behaviour by editing SEASON_ROLE in server.env and re-running",
        "//     python3 bin/season-profile.py --apply",
        "// The role/flag matrix lives in that script, not here.",
        "",
    ]
    for name in FLAGS:
        val = "TRUE " if flags[name] else "FALSE"
        lines.append(f"const int {name:<{width}} = {val.strip()};")
    lines.append("")
    return "\n".join(lines)


def strip_comments(src: str) -> str:
    """Blank out // line comments and /* */ blocks.

    The wiring check MUST run on code only. Every one of these consumers
    explains in a comment which SP_ flag drives it and why it must not go back
    to a literal -- so a plain substring search over the file matches that
    comment and passes even when the code beside it has been hardcoded. That is
    not hypothetical: it is exactly what happened the first time this check was
    written, and it made the gate report a clean tree while the cheat chest was
    wired to TRUE.

    String literals are not considered: no SP_ constant name appears inside one,
    and treating them properly would mean a real lexer for no benefit.
    """
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    return src


def check_wiring() -> list[str]:
    """Return a list of broken-wiring complaints (empty == all good)."""
    problems: list[str] = []
    for filename, const, why in WIRING:
        path = UNPACKED / filename
        if not path.exists():
            problems.append(f"{filename}: missing - {why}")
            continue
        code = strip_comments(path.read_text(encoding="utf-8"))
        wanted = (const,) if isinstance(const, str) else const
        if not any(re.search(rf"\b{re.escape(c)}\b", code) for c in wanted):
            problems.append(
                f"{filename}: no reference to {' or '.join(wanted)} in code "
                f"- {why}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write the changes")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if anything is out of date (build gate)")
    ap.add_argument("--diff", action="store_true", help="show full unified diffs")
    args = ap.parse_args()

    try:
        env = load_env(REPO / "server.env")
        role = env.get("SEASON_ROLE", "")
        if not role:
            raise ProfileError(
                "SEASON_ROLE is unset in server.env — the season block is "
                "required (see README.md 'Season identity')")
        if role not in PROFILE:
            raise ProfileError(
                f"SEASON_ROLE must be {'|'.join(PROFILE)}, got {role!r}")
    except ProfileError as e:
        print(f"season-profile: error: {e}", file=sys.stderr)
        return 2

    flags = PROFILE[role]
    summary = " ".join(f"{n.removeprefix('SP_').lower()}="
                       f"{'on' if flags[n] else 'off'}" for n in FLAGS)
    print(f"role={role}  {summary}")
    print()

    want = render(role)
    have = GENERATED.read_text(encoding="utf-8") if GENERATED.exists() else ""
    stale = want != have

    problems = check_wiring()
    for p in problems:
        print(f"  WIRING BROKEN: {p}")
    if problems:
        print()

    if stale:
        rel = GENERATED.relative_to(REPO)
        print(f"{rel}")
        print(f"    - {'regenerate' if have else 'create'} for role={role}")
        if args.diff:
            for line in difflib.unified_diff(
                    have.splitlines(True), want.splitlines(True),
                    f"a/{rel}", f"b/{rel}"):
                print("    " + line.rstrip("\n"))
        print()
    elif not problems:
        print("up to date — nothing to change")

    if args.check:
        if problems:
            print("season-profile: FAILED — a consumer stopped reading its flag. "
                  "Re-wire it; do not 'fix' this by editing the generated file.")
            return 1
        if stale:
            print("season-profile: FAILED — unpacked/season_prof_inc.nss is out "
                  "of date with SEASON_ROLE. Run: python3 bin/season-profile.py --apply")
            return 1
        return 0

    # Broken wiring is never fixable by writing the generated file, so say so
    # rather than reporting a clean apply over a tree that ignores the output.
    if problems:
        print("season-profile: refusing to write while wiring is broken — the "
              "generated flags would have no effect.", file=sys.stderr)
        return 2

    if not stale:
        return 0

    if not args.apply:
        print("Re-run with --apply to write (or --diff to see the change).")
        return 0

    GENERATED.write_text(want, encoding="utf-8")
    print(f"wrote {GENERATED.relative_to(REPO)}.")
    print("Next: repack and deploy. A second --apply must produce no diff.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
