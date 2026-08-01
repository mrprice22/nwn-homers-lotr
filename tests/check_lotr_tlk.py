#!/usr/bin/env python3
"""Build gate: the module's custom TLK must stay coherent.

The module names exactly one custom TLK (unpacked/module.ifo.json ->
Mod_CustomTlk). As of the Legendary Feats work that is **lotr**, built from
CEP's cep.tlk by bin/build-lotr-tlk, because feat.2da's NAME and DESCRIPTION
columns are strref-only and cannot hold an inline string.

Three things can break it, none of which any other check would catch:

1. **A shifted CEP index.** lotr.tlk[0..41100] must equal cep.tlk exactly. One
   inserted or dropped entry silently repoints CEP-sourced item and creature
   names and descriptions across the whole module. There is no in-game symptom
   until someone reads a wrong tooltip, and no other gate looks at the TLK.
2. **A rebuilt-but-not-regenerated table.** tlk/ is gitignored (regenerable, see
   README.md "Rebuild from scratch"), so lotr.tlk is a local build artefact. A
   stale one carries strings that no longer match the generator's table, and the
   2DA rows that point at those strrefs read as the old text.
3. **A half-done TLK swap.** Mod_CustomTlk still saying "cep" while 2DA rows
   carry 0x01000000-offset strrefs from our block yields blank names in game,
   because those indices do not exist in cep.tlk.

This gate re-derives our block from bin/build-lotr-tlk's own owned_strings()
— its OWNED_STRINGS table plus the feat names and descriptions it pulls from
bin/gen-legendary-feats.py — rather than transcribing the strings a second time,
the idiom tests/check_epic_tables.py already uses for the caster tables.

It does NOT check the *installed* TLK: a correct tlk/lotr.tlk that was never
copied into NWN_HOME_DIR/tlk (or never pushed through bin/refresh-nwsync) is
still dead in game. `bin/build-lotr-tlk --apply --install` handles that.

On a fresh clone tlk/cep.tlk does not exist and neither does nwn_tlk; the gate
warns and passes rather than blocking a repack on game data it cannot reach.

Exit 0 = coherent, 1 = drifted.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GENERATOR = REPO / "bin" / "build-lotr-tlk"
BASE_TLK = REPO / "tlk" / "cep.tlk"
OUT_TLK = REPO / "tlk" / "lotr.tlk"
MODULE_IFO = REPO / "unpacked" / "module.ifo.json"

EXPECTED_CUSTOM_TLK = "lotr"


def load_generator():
    if not GENERATOR.exists():
        return None
    # The generator has no .py extension (it is a bin/ command), so importlib
    # cannot infer a loader — name one explicitly or spec_from_file_location
    # returns None.
    spec = importlib.util.spec_from_file_location(
        "build_lotr_tlk", GENERATOR,
        loader=importlib.machinery.SourceFileLoader("build_lotr_tlk", str(GENERATOR)),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def nwn_tlk_bin():
    override = os.environ.get("NWN_TLK")
    for c in ([override] if override else []) + [
        str(Path.home() / ".nimble" / "bin" / "nwn_tlk"),
        shutil.which("nwn_tlk"),
    ]:
        if c and Path(c).is_file() and os.access(c, os.X_OK):
            return c
    return None


def tlk_entries(tool, path):
    out = subprocess.run(
        [tool, "-i", str(path), "-l", "tlk", "-k", "json"],
        check=True, capture_output=True,
    ).stdout.decode("utf-8")
    return {e["id"]: e.get("text", "") for e in json.loads(out)["entries"]}


def check_module_ifo(problems):
    if not MODULE_IFO.exists():
        problems.append(f"{MODULE_IFO} is missing")
        return
    data = json.loads(MODULE_IFO.read_text(encoding="utf-8"))
    got = (data.get("Mod_CustomTlk") or {}).get("value")
    if got != EXPECTED_CUSTOM_TLK:
        problems.append(
            f"module.ifo.json Mod_CustomTlk is {got!r}, expected "
            f"{EXPECTED_CUSTOM_TLK!r} — the module would resolve our custom "
            "strrefs against the wrong table and show blank feat names"
        )


def check_tlk(problems, gen):
    tool = nwn_tlk_bin()
    if tool is None:
        print("warn: nwn_tlk not found — skipping the TLK content check")
        return
    if not BASE_TLK.exists():
        print(f"warn: {BASE_TLK} not present (regenerable, gitignored) — "
              "skipping the TLK content check")
        return
    if not OUT_TLK.exists():
        problems.append(
            f"{OUT_TLK} is missing — run: bin/build-lotr-tlk --apply --install"
        )
        return

    base = tlk_entries(tool, BASE_TLK)
    ours = tlk_entries(tool, OUT_TLK)
    start = gen.BLOCK_START
    # owned_strings(), not OWNED_STRINGS: the block is the generator's own table
    # plus the legendary feat names and descriptions it pulls from
    # bin/gen-legendary-feats.py.
    expected = gen.owned_strings()

    # 1. CEP's own indices must survive untouched.
    prefix = {i: t for i, t in ours.items() if i < start}
    if prefix != base:
        shifted = sorted(
            i for i in set(prefix) | set(base)
            if prefix.get(i) != base.get(i)
        )
        problems.append(
            f"lotr.tlk diverges from cep.tlk below index {start} at "
            f"{len(shifted)} entr{'y' if len(shifted) == 1 else 'ies'} "
            f"(first: {shifted[:5]}) — every CEP name and description at or "
            "after that index is now repointed. Rebuild with "
            "bin/build-lotr-tlk --apply; do not hand-edit the TLK."
        )

    # 2. Our block must match the generator's table exactly, and stop there.
    for pos, want in enumerate(expected):
        idx = start + pos
        got = ours.get(idx)
        if got != want:
            problems.append(
                f"lotr.tlk index {idx} (strref {idx + gen.CUSTOM_TLK_OFFSET}) "
                f"is {got!r}, generator says {want!r} — stale build, re-run "
                "bin/build-lotr-tlk --apply"
            )
    extra = sorted(i for i in ours if i >= start + len(expected))
    if extra:
        problems.append(
            f"lotr.tlk has {len(extra)} entr{'y' if len(extra) == 1 else 'ies'} "
            f"above the generator's block (first: {extra[:5]}) — a string was "
            "removed from the block — either bin/build-lotr-tlk's OWNED_STRINGS "
            "or a feat in bin/gen-legendary-feats.py. Both lists are "
            "append-only: removing an entry moves every strref after it."
        )


def main():
    problems = []
    gen = load_generator()
    if gen is None:
        problems.append(
            f"{GENERATOR} is missing — nothing owns the module's custom TLK")
    else:
        if not gen.owned_strings():
            problems.append(
                "bin/build-lotr-tlk OWNED_STRINGS is empty — lotr.tlk would be "
                "an exact copy of cep.tlk and this gate would prove nothing")
        check_tlk(problems, gen)
    check_module_ifo(problems)

    if problems:
        print("FAIL: custom TLK (lotr.tlk) has drifted\n", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print("ok: custom TLK coherent (cep.tlk prefix intact, owned block current)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
