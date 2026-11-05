#!/usr/bin/env python3
"""Build gate: Season 3 loot tables (roadmap lo-loot-core).

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
        module-index/item_index.json is present - it is gitignored).

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
    if not lm.INCLUDE.exists() or lm.INCLUDE.read_text() != gen.nss_include(data):
        errs.append("unpacked/loot_data_inc.nss is stale. Re-run: python3 bin/gen-loot-tables.py --apply")
    if errs:
        print("FAIL loot tables:")
        for e in errs:
            print("  - " + e)
        return 1
    print("ok loot tables: %d rarities, %d affixes, %d named, %d profiles"
          % (len(data["rarity"]["tiers"]), len(data["affixes"]["affixes"]),
             len(data["named"]["items"]), len(data["sources"]["profiles"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
