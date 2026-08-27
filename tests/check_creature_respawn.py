#!/usr/bin/env python3
"""Build gate: every placed creature must have a respawn path.

Respawn is decided solely by whether a creature's OnDeath script reaches
SE_DoCreatureRespawn() (unpacked/se_respawn_inc.nss). A placed creature whose
effective ScriptDeath -- the INSTANCE's where it overrides the blueprint's --
never gets there is dead until the next server restart, which is invisible in
the toolset and in every diff.

Deliberate exceptions live in tests/respawn_ignore.json, each with a reason.

The scan is imported from bin/audit-creature-respawn.py rather than
re-implemented, so the gate and the generated CLAUDE-respawn-audit.md can never
disagree (same arrangement as check_map_notes.py and gen-map-notes.py).
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location(
    "audit_creature_respawn", ROOT / "bin" / "audit-creature-respawn.py")
_audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_audit)


def main():
    rows = _audit.scan()
    bad = _audit.offenders(rows)
    if not bad:
        print(f"check_creature_respawn: ok — {len(rows)} placed creatures, "
              f"{sum(r['ignored'] for r in rows)} allowlisted")
        return 0

    print(f"check_creature_respawn: {len(bad)} placed creature(s) never respawn "
          f"and are not in tests/respawn_ignore.json")
    for r in bad:
        src = "instance" if r["from_instance"] else "blueprint"
        print(f"  {r['area']:18s} {r['resref']:20s} {r['name'][:32]:32s} "
              f"OnDeath={r['script_death'] or '(blank)'} ({src}, {r['kind']})")
    print("\nFix: point ScriptDeath at a handler that reaches "
          "SE_DoCreatureRespawn() — x2_def_ondeath for an ordinary creature — "
          "on the placed instance AND the blueprint. If the creature is meant "
          "to stay dead (corpse prop, unkillable utility NPC, hak-only "
          "blueprint), add it to tests/respawn_ignore.json with a reason.")
    print("Report: python3 bin/audit-creature-respawn.py --write")
    return 1


if __name__ == "__main__":
    sys.exit(main())
