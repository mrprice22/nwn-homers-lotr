#!/usr/bin/env python3
"""Audit every placed creature for whether it ever comes back.

Respawn in this module is decided by ONE thing: whether the creature's OnDeath
script reaches SE_DoCreatureRespawn() in unpacked/se_respawn_inc.nss. There is
no NO_RESPAWN variable and no per-creature timer. A placed creature whose
ScriptDeath points at a handler that never calls it is gone until the next
server restart -- which is what "I killed these an hour ago and they never came
back" reports are.

Two traps this exists to catch:

  * the PLACED INSTANCE's ScriptDeath wins at runtime, so a blueprint fixed in
    isolation proves nothing (this is how the Wart Gondorian Gate Captain kept
    a false countdown on the Roll of the Fallen);
  * se_respawn_inc re-creates from the BLUEPRINT resref, so a creature whose
    blueprint lives only in a hak comes back as the generic hak creature, with
    every instance override (name, faction, gear) lost.

Classification is imported from bin/gen-boss-registry.py so the board, the wiki
and this audit can never disagree about what "respawns" means.

    python3 bin/audit-creature-respawn.py            # report to stdout
    python3 bin/audit-creature-respawn.py --write     # + CLAUDE-respawn-audit.md
                                                      #   + module-index/respawn_audit.json

tests/check_creature_respawn.py imports scan() from here, so the gate and the
report always describe the same module.
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin"
sys.path.insert(0, str(BIN))

import boss_index as bi                                    # noqa: E402
from boss_index import UNPACKED, gv, locstr, area_name      # noqa: E402

# gen-boss-registry.py isn't an importable module name (hyphens), so load it by
# path rather than duplicating its ExecuteScript-chain-following classifier.
_spec = importlib.util.spec_from_file_location(
    "gen_boss_registry", BIN / "gen-boss-registry.py")
_gbr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gbr)
death_respawn_kind = _gbr._death_respawn_kind

IGNORE_FILE = ROOT / "tests" / "respawn_ignore.json"
EXTERNAL_FILE = ROOT / "tests" / "respawn_external_blueprints.json"
MD_OUT = ROOT / "CLAUDE-respawn-audit.md"
JSON_OUT = ROOT / "module-index" / "respawn_audit.json"


def load_ignore():
    """{(area, resref): reason} for placements deliberately left un-respawning."""
    if not IGNORE_FILE.exists():
        return {}
    data = json.loads(IGNORE_FILE.read_text())
    return {(e["area"], e["resref"]): e.get("reason", "") for e in data["ignore"]}


def external_resrefs():
    """Creature resrefs that resolve OUTSIDE unpacked/ (base game, CEP, haks).

    se_respawn_inc re-creates from the blueprint resref, so a respawning
    creature whose resref resolves nowhere is deleted on death rather than
    respawned. Resolving that needs the NWN install, which a build gate cannot
    assume, so the answer is checked in here and refreshed deliberately with
    --refresh-external.
    """
    if not EXTERNAL_FILE.exists():
        return None
    return {r.lower()
            for r in json.loads(EXTERNAL_FILE.read_text())["resolves_outside_module"]}


def refresh_external():
    """Re-derive the external list from the live NWN install + hak folder."""
    import subprocess
    haks = sorted((Path.home() / ".local/share/Neverwinter Nights/hak").glob("*.hak"))
    cmd = ["nwn_resman_grep", "--all"]
    if haks:
        cmd += ["--erfs", ",".join(str(h) for h in haks)]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    found = sorted({line.strip()[:-4].lower() for line in out.splitlines()
                    if line.strip().lower().endswith(".utc")})
    EXTERNAL_FILE.write_text(json.dumps({
        "_comment": [
            "Creature blueprint resrefs that resolve OUTSIDE unpacked/ -- the base",
            "game, CEP, and every hak in the NWN hak folder. se_respawn_inc",
            "re-creates from the resref, so a respawning placement whose resref is",
            "in neither unpacked/ nor this list is DELETED on death, not respawned.",
            "tests/check_creature_respawn.py fails the repack on that.",
            "Regenerate (needs the NWN install) with:",
            "  python3 bin/audit-creature-respawn.py --refresh-external",
        ],
        "resolves_outside_module": found,
    }, indent=1) + "\n")
    print(f"wrote {EXTERNAL_FILE.relative_to(ROOT)} ({len(found)} resrefs)")


def scan():
    """One row per placed creature instance, worst first.

    kind: 'standard' (se_respawn_inc, 900s) | 'legacy' (re-creates on its own
    timer) | 'none' (stays dead until a restart).
    """
    ignore = load_ignore()
    external = external_resrefs()
    rows = []
    for git in sorted(UNPACKED.glob("*.git.json")):
        area = git.name.replace(".git.json", "")
        data = json.loads(git.read_text())
        for c in gv(data.get("Creature List")) or []:
            rr = gv(c.get("TemplateResRef")) or ""
            bp = bi.load_blueprint(rr)
            inst_death = (gv(c.get("ScriptDeath")) or "").lower()
            death = inst_death or (bp["script_death"] if bp else "")
            name = (locstr(c.get("FirstName")) + " "
                    + locstr(c.get("LastName"))).strip()
            if not name:
                name = bp["name"] if bp else rr
            rows.append({
                "area": area,
                "area_name": area_name(area),
                "resref": rr,
                "name": name,
                "tag": gv(c.get("Tag")) or (bp["tag"] if bp else ""),
                "script_death": death,
                "from_instance": bool(inst_death),
                "overrides_blueprint": bool(
                    inst_death and bp and inst_death != bp["script_death"]),
                "blueprint_in_module": bp is not None,
                "blueprint_resolves": (
                    True if bp is not None
                    else (None if external is None else rr.lower() in external)),
                "cr": bp["cr"] if bp else None,
                "plot": bool(bp["plot"]) if bp else False,
                "immortal": bool(bp["immortal"]) if bp else False,
                "kind": death_respawn_kind(death),
                "ignored": (area, rr) in ignore,
                "ignore_reason": ignore.get((area, rr), ""),
            })
    order = {"none": 0, "legacy": 1, "standard": 2}
    rows.sort(key=lambda r: (r["ignored"], order[r["kind"]],
                             -(r["cr"] or 0), r["area"], r["resref"]))
    return rows


def offenders(rows):
    """Rows the build gate fails on, each tagged with why.

    'no-respawn'  — the OnDeath never reaches SE_DoCreatureRespawn().
    'unresolvable'— it does, but the blueprint resref exists in no container, so
                    CreateObject returns nothing and the creature is deleted on
                    death instead of respawned. Same symptom, different cause.
    """
    bad = []
    for r in rows:
        if r["ignored"]:
            continue
        if r["kind"] != "standard":
            bad.append(dict(r, fault="no-respawn"))
        elif r["blueprint_resolves"] is False:
            bad.append(dict(r, fault="unresolvable"))
    return bad


def render_md(rows):
    bad = offenders(rows)
    ign = [r for r in rows if r["ignored"]]
    out = [
        "# Creature respawn audit",
        "",
        "**Generated** by `bin/audit-creature-respawn.py` — do not hand-edit; "
        "re-run it instead.",
        "",
        "Every placed creature instance in `unpacked/*.git.json`, classified by "
        "whether its *effective* OnDeath script (the instance's `ScriptDeath` "
        "where it overrides the blueprint's) reaches `SE_DoCreatureRespawn()`.",
        "",
        f"- placed instances: **{len(rows)}**",
        f"- respawn on the standard 900 s timer: "
        f"**{sum(r['kind'] == 'standard' for r in rows)}**",
        f"- allowlisted in `tests/respawn_ignore.json`: **{len(ign)}**",
        f"- **not respawning and not allowlisted: {len(bad)}** "
        f"(`tests/check_creature_respawn.py` fails the repack on these)",
        "",
    ]
    if bad:
        out += ["## Failing — never comes back", "",
                "`no-respawn` = the OnDeath never respawns it. `unresolvable` = "
                "it tries, but the blueprint resref exists nowhere, so "
                "`CreateObject` returns nothing and the creature is deleted.", "",
                "| Area | Creature | ResRef | CR | OnDeath | fault |",
                "|---|---|---|---:|---|---|"]
        for r in bad:
            cr = f"{r['cr']:.0f}" if r["cr"] is not None else "—"
            out.append(f"| {r['area_name']} | {r['name']} | `{r['resref']}` | "
                       f"{cr} | `{r['script_death'] or '(blank)'}` | {r['fault']} |")
        out.append("")

    odd = [r for r in rows if r["overrides_blueprint"]]
    if odd:
        out += ["## Instance overrides the blueprint's OnDeath", "",
                "The instance wins at runtime, so fixing only the blueprint "
                "changes nothing in game.", "",
                "| Area | Creature | ResRef | instance OnDeath | kind |",
                "|---|---|---|---|---|"]
        for r in odd:
            out.append(f"| {r['area_name']} | {r['name']} | `{r['resref']}` | "
                       f"`{r['script_death']}` | {r['kind']} |")
        out.append("")

    hak = [r for r in rows if not r["blueprint_in_module"]
           and r["kind"] == "standard" and r["blueprint_resolves"] is not False]
    if hak:
        out += ["## Respawns, but the blueprint is not in the module", "",
                "`se_respawn_inc` re-creates from the blueprint resref. These "
                "resolve to a base-game/CEP blueprint, so the creature does "
                "come back — as the *generic* one, losing every instance "
                "override (name, faction, gear).", "",
                "| Area | Creature | ResRef |", "|---|---|---|"]
        for r in hak:
            out.append(f"| {r['area_name']} | {r['name']} | `{r['resref']}` |")
        out.append("")

    if ign:
        out += ["## Allowlisted (deliberately never respawn)", "",
                "| Area | Creature | ResRef | Reason |", "|---|---|---|---|"]
        for r in ign:
            out.append(f"| {r['area_name']} | {r['name']} | `{r['resref']}` | "
                       f"{r['ignore_reason']} |")
        out.append("")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="write CLAUDE-respawn-audit.md and the JSON manifest")
    ap.add_argument("--refresh-external", action="store_true",
                    help="re-derive tests/respawn_external_blueprints.json from "
                         "the NWN install (needs nwn_resman_grep)")
    args = ap.parse_args()

    if args.refresh_external:
        refresh_external()

    rows = scan()
    bad = offenders(rows)
    print(f"placed instances: {len(rows)}   "
          f"standard: {sum(r['kind'] == 'standard' for r in rows)}   "
          f"legacy: {sum(r['kind'] == 'legacy' for r in rows)}   "
          f"none: {sum(r['kind'] == 'none' for r in rows)}   "
          f"allowlisted: {sum(r['ignored'] for r in rows)}")
    if bad:
        print(f"\n=== NOT RESPAWNING ({len(bad)}) ===")
        for r in bad:
            cr = f"{r['cr']:7.0f}" if r["cr"] is not None else "      —"
            print(f"  {cr}  {r['resref']:20s} {r['name'][:32]:32s} "
                  f"{r['area']:18s} {r['fault']:12s} "
                  f"OnDeath={r['script_death'] or '(blank)'}")
    else:
        print("\nevery placed creature has a respawn path (or is allowlisted).")

    if args.write:
        MD_OUT.write_text(render_md(rows))
        JSON_OUT.parent.mkdir(exist_ok=True)
        JSON_OUT.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
        print(f"\nwrote {MD_OUT.relative_to(ROOT)} and "
              f"{JSON_OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
