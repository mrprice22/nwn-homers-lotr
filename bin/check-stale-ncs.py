#!/usr/bin/env python3
"""Prove whether a built .mod's compiled scripts match current source.

## The problem this exists for

nasher decides what to recompile from `.nss` timestamps. A script that merely
*includes* the file you edited has not itself changed, so its old `.ncs` is
packed unchanged -- and plain `nasher --clean` does not fix it either, because
stale binaries linger in `.nasher/tmp/` and fool the same check.

The result is a MIXED module: brand-new scripts use the new include, every
existing consumer uses the old one. It is silent, and the symptom points at the
wrong file. When a new table was added to an include's init function, every
script that READ the table was current and the one that CREATED it was stale, so
the in-game error named the readers.

    bin/check-stale-ncs.py --include cp_db.nss     # the usual question
    bin/check-stale-ncs.py --scripts onmoduleload  # specific scripts
    bin/check-stale-ncs.py --include cp_inc.nss --mod some_old_build.mod

Exits 1 if anything is stale, so it can gate a deploy.

## How it decides

It recompiles the scripts from CURRENT source and byte-compares against what the
module actually carries. NWScript compilation is deterministic, so a difference
means the packed copy was built from something else.

An earlier version of this tool grepped the `.ncs` for a string and MISSED the
real case, because the string lived in the include and the stale consumer's own
source never mentioned it. Comparing bytes needs no such guess -- do not
"optimise" it back into a string search.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"


def tool(name: str) -> str:
    """~/.nimble/bin is not always on PATH (desktop actions, cron)."""
    found = shutil.which(name)
    if found:
        return found
    candidate = Path.home() / ".nimble" / "bin" / name
    if candidate.exists():
        return str(candidate)
    sys.exit(f"{name} not found on PATH or in ~/.nimble/bin")


def default_mod() -> Path | None:
    env = REPO / "server.env"
    home = module = None
    if env.exists():
        for line in env.read_text().splitlines():
            m = re.match(r'^\s*(NWN_HOME_DIR|NWN_MODULE)\s*=\s*(.*)$', line)
            if not m:
                continue
            val = m.group(2).split('#')[0].strip().strip('"').strip("'")
            val = val.replace("$HOME", str(Path.home()))
            if m.group(1) == "NWN_HOME_DIR":
                home = Path(val)
            else:
                module = val
    return home / "modules" / f"{module}.mod" if home and module else None


def includes_of(stem: str) -> set[str]:
    p = UNPACKED / f"{stem}.nss"
    if not p.exists():
        return set()
    text = p.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r'^\s*#include\s+"([^"]+)"', text, re.M))


def consumers_of(include_stem: str) -> list[str]:
    """Every script that reaches this include, directly or through others."""
    direct: dict[str, set[str]] = {}
    for p in UNPACKED.glob("*.nss"):
        direct[p.stem] = includes_of(p.stem)

    reaches: dict[str, bool] = {}

    def walk(stem: str, seen: set[str]) -> bool:
        if stem in reaches:
            return reaches[stem]
        if stem in seen:                    # cyclic include; treat as no
            return False
        seen = seen | {stem}
        got = include_stem in direct.get(stem, set()) or any(
            walk(inc, seen) for inc in direct.get(stem, set()))
        reaches[stem] = got
        return got

    return sorted(s for s in direct if s != include_stem and walk(s, set()))


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--include", help="check every script that includes this file")
    ap.add_argument("--scripts", nargs="+", help="check these script names")
    ap.add_argument("--mod", type=Path, help="module to inspect (default: this repo's install)")
    a = ap.parse_args()
    if not a.include and not a.scripts:
        ap.error("give --include FILE or --scripts NAME...")

    mod = Path(a.mod).resolve() if a.mod else default_mod()
    if not mod or not mod.exists():
        sys.exit(f"module not found: {mod}\nBuild one first, or pass --mod.")

    names = list(a.scripts or [])
    if a.include:
        names += consumers_of(Path(a.include).stem)
    names = sorted(set(names))

    print(f"module:  {mod}")
    print(f"checking {len(names)} script(s) against current source\n")

    erf, comp = tool("nwn_erf"), tool("nwn_script_comp")
    nwnroot = Path.home() / ".local/share/Steam/steamapps/common/Neverwinter Nights"

    packed = Path(tempfile.mkdtemp(prefix="stale-packed-"))
    fresh = Path(tempfile.mkdtemp(prefix="stale-fresh-"))
    stale, unpacked_only, failed, checked = [], [], [], 0
    try:
        subprocess.run([erf, "-x", "-f", str(mod)] + [f"{n}.ncs" for n in names],
                       cwd=packed, capture_output=True)
        for n in names:
            got = packed / f"{n}.ncs"
            if not got.exists():
                unpacked_only.append(n)     # an include, or simply not packed
                continue
            # -o names the output FILE. (-d is the directory form, and only for
            # the -c batch mode.) Passing a directory here compiles happily and
            # writes nothing, which is how this check silently measured zero
            # scripts the first time it was run.
            built = fresh / f"{n}.ncs"
            r = subprocess.run(
                [comp, "--root", str(nwnroot), "--dirs", str(UNPACKED),
                 "-o", str(built), str(UNPACKED / f"{n}.nss")],
                capture_output=True, text=True)
            if not built.exists():
                failed.append((n, (r.stderr or r.stdout).strip().splitlines()[-1:]))
                continue
            checked += 1
            if built.read_bytes() != got.read_bytes():
                stale.append(n)
    finally:
        shutil.rmtree(packed, ignore_errors=True)
        shutil.rmtree(fresh, ignore_errors=True)

    print(f"compared {checked} compiled script(s)")
    if unpacked_only:
        print(f"  {len(unpacked_only)} not packed as .ncs (includes and the like)")
    if failed:
        print(f"  {len(failed)} could not be recompiled:")
        for n, why in failed:
            print(f"      {n}: {' '.join(why) or 'unknown'}")
    if not stale:
        if not checked:
            print("\nNothing was actually compared - treat this as NO ANSWER, "
                  "not a pass.")
            return 1
        print("\nOK - every one matches a fresh compile of current source.")
        return 0

    print(f"\nSTALE - {len(stale)} script(s) in the module differ from current source:\n")
    for n in stale:
        print(f"  {n}.ncs")
    print("\nFix: rebuild with nwn_manager/bin/repack-homers-lotr-clean.")
    print("A plain repack will NOT fix it - see CLAUDE-gotchas.md.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
