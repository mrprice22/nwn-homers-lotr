# Rolled loot (Season 3 Loot Overhaul) — developer reference

Roadmap epic `loot-overhaul`; the design and phase plan are in
[docs.manual/Draft/Loot-Overhaul.html](docs.manual/Draft/Loot-Overhaul.html). This file
is the working reference for the code as built. Phase 2 (`lo-loot-core`) built the
engine; phases 3–7 plug sources into it.

## One data source, three readers

```
loot/*.json ──► bin/loot_model.py ──┬─► bin/gen-loot-tables.py ─► unpacked/loot_data_inc.nss ─► loot_inc.nss (game)
                                    ├─► tests/check_loot_tables.py   (repack gate, in tests/smoke-test)
                                    └─► bin/loot-sim.py               (balance tables)
```

| File | Holds |
|---|---|
| `loot/rarity.json` | 5 tiers (index = `LOOT_RARITY`): weight, affix count, per-mille chances (downside, unidentified, upgrades, named), `roll_bias`, value budget curve by loot level |
| `loot/levels.json` | CR → loot level 1–60 (`cr_points`, piecewise-linear); `boss_overrides` for Phase 4 |
| `loot/bases.json` | 7 categories → base-item rows, weights, appearance donors |
| `loot/affixes.json` | 68 affixes: type/sub, cost **ladder** (rows in ascending power), level **window** into the ladder, categories, weight, exclusion **group**, role, name words |
| `loot/named.json` | curated existing items a top-tier roll may award (draft, admin review pending) |
| `loot/sources.json` | profiles (`lab`, `chest_*`, `creature`, `boss`): category weights, roll count, rarity floor |
| `loot/_costs.json` | **generated** 2DA cost snapshot so the gate and sim need no NWN install |

**After any change to `loot/*.json`:** `python3 bin/gen-loot-tables.py --apply`, then
`python3 bin/loot-sim.py`, and commit the JSON and the include together. Then build with
**`repack-homers-lotr-clean`**: `loot_data_inc` is an include, and nasher's incremental
compile does not reliably rebuild the scripts that include it (CLAUDE.md, "Editing a .nss
include").

- `--refresh-costs` re-reads the 2DAs (stock + the module's CEP haks + `hak_2da/`, via
  `nwn_resman_cat`). Re-run it after a `hak_2da/` cost-table change.
- `--harvest-donors` refills `bases.json` appearances from the module's own `.uti` files.

## The rules the gate enforces

These are in `loot_model.validate()`, and every one fails the repack:

- **Supported property types only.** An affix type must be in `SUPPORTED_IP`. That table
  is also what the generator emits `Loot_MakeIP()` from, so the runtime switch cannot drift
  from the data.
- **Banned outright:** Haste (attacks per round), Divine damage, and critical-hit immunity
  (because of the devcrit rework). `season3-meta-shakeup` asks for new axes, not bigger
  numbers on the old ones.
- **Valid rows only.** Every subtype and cost row must exist in its 2DA, and every window
  must sit inside its ladder.
- **No more than the forge allows.** A tier's maximum affix count, plus the downside and the
  bonus upside it buys, must stay ≤ `FORGE_LEGAL_MAX_PROPS` (6).
- **Every tier's minimum affix set must fit its budget**, for every category at levels 1,
  20, 40 and 60.
- **The top-tier budget stays below the most valuable obtainable item.** This check reads
  `module-index/item_index.json`, which is gitignored, and is skipped when that file is absent.
- **Named items** must exist and must not be Plot, Cursed or stacked.

## Runtime (`loot_inc.nss`)

`Loot_Roll(nLevel, nRarityFloor, sProfile, oBeneficiary, oDest)` returns the item.
`Loot_RollProfile(...)` makes a profile's full drop. `bin/loot_model.py roll()` is its
Python mirror: **change one, change the other.**

- **Built in the forge vault, not on the destination.** The item is created in
  `ForgeHolder()` from `forge_blank_<base>`, priced there, and only then copied to `oDest`.
  Its tag is `loot_<base>`, never `forge_blank_*`.
- **The budget is enforced transactionally.** The candidate set is priced on a scratch
  blank with the engine's `GetGoldPieceValue`, and the last upside is stepped down its
  ladder, then dropped, until the set fits. Only the fitting set is applied to the item.
  The Python value is an estimate (it matches about 88% of blueprint costs); the engine
  value is the one that counts.
- **Self-check.** After construction, each property's type and cost row are compared with
  the request. A mismatch logs `LOOT: affix '<id>' built the wrong property` and the affix
  is skipped. Grep the server log for `LOOT:` after any data change.
- **Stamps** (`.bic`-persistent, they survive the party roll's `CopyItem(..., TRUE)`):
  `LOOT_VER`, `LOOT_LVL`, `LOOT_RARITY`, `LOOT_PROFILE`, `LOOT_AFX_N`,
  `LOOT_AFX_<i>` = `ForgePropSig` of each random property, and `LOOT_NAMED` for
  named-pool items. Phase 7's reforge removes exactly the `LOOT_AFX_*` signatures.
- **Telemetry.** The `lootdb` table `loot_roll_log` records every `lab` roll plus every
  Epic-or-better roll, not every roll. A synchronous commit per chest item would be felt
  as lag.

## Loot Lab

Rest menu → Admin Options → **[Admin] Loot Lab** (`emotewand.dlg` Entry 19,
`lootlab_*.nss`). It can:

- set the loot level (±1 / ±10) and cycle the rarity floor (tokens 6450 / 6451);
- roll 1 or 10 items into your pack;
- stock the nearest container with 5 items;
- dump every rolled item's stamps with its engine value against its budget.

Phases 5 and 7 add "grant a gem" and "grant a Shard of Fate" here.

## Value budgets: why they exceed the forge caps

The budgets are anchored to obtainable gear, not to the forge caps (admin decision,
2026-11-05). `bin/loot-sim.py --calibrate` prints the gear percentiles. A roll worth more
than a forge's cap simply cannot be enchanted further there, exactly like the existing
top gear (`modifyitem` refuses any change that would push past the cap). No forge rule
changed.
