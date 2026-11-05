#!/usr/bin/env python3
"""Build gate: Season 3 loot tables (roadmap lo-loot-core + Phase 3 containers).

loot/*.json is the one source of truth for rolled loot; bin/gen-loot-tables.py
compiles it into unpacked/loot_data_inc.nss, which the game reads.  This gate
fails the repack when:

  * the committed include is stale (the JSON changed and --apply was not run);
  * the JSON breaks a rule - every check lives in bin/loot_model.py validate():
      - an unknown base-item row, or one with no forge_blank_<row> to build from;
      - an item property type outside SUPPORTED_IP, or a banned one (Haste,
        Divine damage, critical-hit immunity);
      - a subtype or cost row that is not in its 2DA (loot/_costs.json);
      - a level window outside its ladder;
      - a named-pool resref that is missing, Plot, Cursed or stacked;
      - a rarity whose minimum affix set cannot fit its value budget, or whose
        maximum property count exceeds the forge ceiling (6);
      - a top-tier budget above the most valuable obtainable item (only when
        module-index/item_index.json is present - it is gitignored);
  * Phase 3 (chests and containers):
      - an area holds a treasure container but has no level: no hostiles and no
        sources.json area_overrides entry, or loot/area_levels.json predates it
        (level drift elsewhere is only a note, so toolset edits never block);
      - a generated container script (sources.json "scripts" -> unpacked/<name>.nss)
        is stale, missing, or orphaned;
      - a consumables.json / treasure.json item is missing, Plot, Cursed, or (gems)
        carries properties.

Exit 0 = good, 1 = fix the data (or re-run the generator).
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin"))

import importlib.util  # noqa: E402

import loot_model as lm  # noqa: E402

_spec = importlib.util.spec_from_file_location("gen_loot_tables", ROOT / "bin" / "gen-loot-tables.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)


def main() -> int:
    data = lm.load_data()
    item_index = None
    idx = ROOT / "module-index" / "item_index.json"
    if idx.exists():
        d = json.loads(idx.read_text())
        item_index = d["items"] if isinstance(d, dict) else d
    else:
        print("note: module-index/item_index.json absent - skipping the obtainable-gear ceiling check")
    errs = lm.validate(data, item_index)
    # Area levels: a container whose area has no level in the COMMITTED file rolls
    # at level 1 in game, so that fails.  Mere drift (a creature added, a median
    # moved) does not - it would block every routine toolset edit - it is a note.
    fresh = lm.area_levels_doc(data)
    committed = data["area_levels"]["areas"]
    unlevelled = [a for a, e in fresh["areas"].items()
                  if e["chests"] and e["level"] is not None and not (committed.get(a) or {}).get("level")]
    if unlevelled:
        errs.append("treasure container(s) in area(s) with no level in loot/area_levels.json: %s. "
                    "Re-run: python3 bin/gen-area-loot-levels.py --apply, then "
                    "python3 bin/gen-loot-tables.py --apply" % ", ".join(unlevelled))
    drift = [a for a, e in fresh["areas"].items()
             if (committed.get(a) or {}).get("level") != e["level"]]
    if drift:
        print("note: %d area loot level(s) drifted from loot/area_levels.json (%s) - refresh with "
              "gen-area-loot-levels.py --apply + gen-loot-tables.py --apply when convenient"
              % (len(drift), ", ".join(drift[:8]) + (" ..." if len(drift) > 8 else "")))
    if not lm.INCLUDE.exists() or lm.INCLUDE.read_text() != gen.nss_include(data):
        errs.append("unpacked/loot_data_inc.nss is stale. Re-run: python3 bin/gen-loot-tables.py --apply")
    stale, orphans = gen.wrapper_problems(data)
    if stale:
        errs.append("container script(s) stale or missing (generated from sources.json "
                    "\"scripts\"; never hand-edit them): %s. Re-run: python3 "
                    "bin/gen-loot-tables.py --apply" % ", ".join(stale))
    if orphans:
        errs.append("generated container script(s) no longer in sources.json \"scripts\": %s"
                    % ", ".join(o + ".nss" for o in orphans))
    if errs:
        print("FAIL loot tables:")
        for e in errs:
            print("  - " + e)
        return 1
    print("ok loot tables: %d rarities, %d affixes, %d named, %d profiles, %d container "
          "scripts, %d consumables, %d treasure gems"
          % (len(data["rarity"]["tiers"]), len(data["affixes"]["affixes"]),
             len(data["named"]["items"]), len(data["sources"]["profiles"]),
             len(data["sources"].get("scripts", {})), len(data["consumables"]["items"]),
             len(data["treasure"]["gems"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
