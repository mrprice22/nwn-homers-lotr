# Rolled loot (Season 3 Loot Overhaul) — developer reference

Roadmap epic `loot-overhaul`; the design and phase plan are in
[docs.manual/Draft/Loot-Overhaul.html](docs.manual/Draft/Loot-Overhaul.html). This file
is the working reference for the code as built. Phase 2 (`lo-loot-core`) built the
engine; phase 3 (`rng-based-gear-diablo-world-of-warcraft-style`) put it in every chest and
container; phases 4–7 plug the remaining sources into it.

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
| `loot/sources.json` | profiles (`lab`, `chest_*`, `creature`, `boss`): category weights, roll count, rarity floor, and for containers `gear_chance` / `gold_pct` / `gem_chance` / `consumables`; `scripts` (container script → profile); `area_overrides` |
| `loot/area_levels.json` | **generated** by `bin/gen-area-loot-levels.py`: every area's loot level |
| `loot/consumables.json` | consumables a container may hold: resref, level window, weight, stack range (drafted by `bin/gen-loot-consumables.py --draft`, admin-reviewed) |
| `loot/treasure.json` | plain valuable gems a container may pay its gold in |
| `loot/_items.json` | **generated** stock-item snapshot for the two pools (`gen-loot-consumables.py --refresh-items`) |
| `loot/_costs.json` | **generated** 2DA cost snapshot so the gate and sim need no NWN install |

**After any change to `loot/*.json`:** `python3 bin/gen-loot-tables.py --apply` (it also
regenerates the container wrapper scripts), then
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

## Chests and containers (Phase 3)

```
loot/sources.json "scripts" ─► gen-loot-tables.py --apply ─► unpacked/<script>.nss  (30 generated wrappers)
                                                                 └─ #include "loot_chest_inc"
                                                                    LootChest_Refill / LootChest_Once
                                                                    └─ Loot_FillContainer (loot_inc)
```

- **The wrappers are generated, never hand-edited.** `chest_respawner`, `chest_refilllow`,
  `chest_refillhigh`, `chestrespawn{low,high}` (mode `refill`: the 200 s respawning chest, timer
  unchanged), and **local overrides of BioWare's stock scripts** `nw_o2_class*`,
  `nw_o2_general*`, `x2_02_*`, `x0_o2_{any,noam,mlee,rang}*` (mode `once`: filled on first open or
  bash, then `LootChest_ShoutDisturbed`). To retarget a script, change its row and re-run
  `--apply`; the gate fails on a stale, missing or orphaned wrapper. `q_pal_tomb`'s
  `ExecuteScript("nw_o2_classhig")` picks up the override. Bookshelves, potion/gold/kit-specific
  stock scripts, the key chests (`gldchest*`, `*_key`) and the Donations Chest are
  deliberately not in the table.
- **Mode `custom`** = a hand-written script the generator leaves alone; the gate only checks it
  exists and names its profile in quotes. The three **Setti coffers** (`chest_settibelt`,
  `ches_settiring`, `chest_settishld`, Noirinan) use it: they keep `setti_loot_inc`'s one-real-hour
  cooldown and re-lock, and roll `Loot_FillContainer` with profiles `setti_belt` / `setti_ring` /
  `setti_shield` (rarity floor Legendary, at the area's level, 55). Admin request 2026-11-05:
  "top tier loot for the area". The old `my_create{belt,ring,shield}` pools are no longer called.
- **Profile `bases`** (optional list of base-item rows) restricts a profile to those bases,
  named-pool awards included (`LootD_ProfileBaseOk`, `LootD_NamedBase`). Every weighted category
  must contain at least one allowed base or the gate fails.
- **A container rolls at its area's level** (`Loot_ContainerLevel`): its own `LOOT_LEVEL` local
  if set, else `LootD_AreaLevel(area resref)` cached on the area as `LOOT_AREA_LVL`, else level 1
  with a `LOOT:` warning. `LOOT_NONE` on a placeable skips the fill.
- **Area levels:** `bin/gen-area-loot-levels.py` takes the median CR of the area's hostile
  creatures (placed instances + placed encounter pools; hostile = reputation toward players
  ≤ 10 in `repute.fac.json`), through `levels.json`. An area with chests but no hostiles needs
  a `sources.json` `area_overrides` entry with a `reason`; `--suggest` proposes one from the
  nearest levelled areas (`module-index/area_graph.json`), `--table` lists every chest area.
  The gate **fails** only when a chest area has no level; level drift after a toolset edit is
  a printed note, so it never blocks a build. Refresh with `--apply` when convenient.
  Watch single-hostile areas: `bagend001` reads 47 because its one hostile is a CR-424 boss.
- **One fill** (`Loot_FillContainer`, Python mirror `loot_model.chest_contents`): `rolls` gear
  rolls, each at `gear_chance` per mille, at the profile floor; then gold, mean `gold_pct` % of
  the Common budget at the level, paid 50–150% of the mean, as up to 3 treasure gems at
  `gem_chance` (`Loot_PayGems`) with the rest in gold; then `consumables` [min, max] picks from
  the consumables pool, weighted, inside each entry's level window.
- **The consumables pool is packed into fixed-width string chunks** in `loot_data_inc`
  (`LootD_ConsChunk`), not a switch: NWScript compiles a switch to a linear compare chain, and a
  391-case switch inside a weighted-pick loop is TMI territory.
- **Pools:** `gen-loot-consumables.py --draft` builds both from `module-index/item_index.json`:
  obtainable from a store or container (not only carried by a creature), not Plot/Cursed, one
  entry per tag, not looked up by any script (`GetItemPossessedBy`, `GetTag(...) ==`, …; the
  Jasperre AI and stock treasure scripts are ignored), Rogue's Gem excluded on purpose. It
  refuses to overwrite a reviewed pool without `--force`. Stock items are snapshotted to
  `_items.json` so the gate needs no NWN install.
- **Socketable gems** in chests (admin, 2026-11-05) arrive with Phase 5: add a
  `socket_gem_chance` to the container profiles then.
- `python3 bin/loot-sim.py --chests` prints gear, rarity mix, gold, gem share and consumables per
  fill for every container profile, plus chests by area level.

## Loot Lab

Rest menu → Admin Options → **[Admin] Loot Lab** (`emotewand.dlg` Entry 19,
`lootlab_*.nss`). It can:

- set the loot level (±1 / ±10) and cycle the rarity floor (tokens 6450 / 6451);
- roll 1 or 10 items into your pack;
- restock the nearest container: a loot container gets one real fill of its own profile at its
  own loot level (and reports the area's level); anything else gets 5 lab-level items;
- dump every rolled item's stamps with its engine value against its budget.

Phases 5 and 7 add "grant a gem" and "grant a Shard of Fate" here.

## Value budgets: why they exceed the forge caps

The budgets are anchored to obtainable gear, not to the forge caps (admin decision,
2026-11-05). `bin/loot-sim.py --calibrate` prints the gear percentiles. A roll worth more
than a forge's cap simply cannot be enchanted further there, exactly like the existing
top gear (`modifyitem` refuses any change that would push past the cap). No forge rule
changed.
