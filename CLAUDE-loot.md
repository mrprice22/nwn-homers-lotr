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
- **Area levels:** `bin/gen-area-loot-levels.py` takes the **median CR** (`levels.json`
  `area_percentile` 50; stored as `area_cr`) of the area's hostile creatures (placed instances +
  placed encounter pools; hostile = reputation toward players ≤ 10 in `repute.fac.json`),
  through `levels.json`. Area levels are **loot levels**, not CRs: CR 55 = 31, CR 250 = 45,
  CR 1000 = 55. The 75th percentile was tried and reverted (2026-11-06): it moved Edoras only
  31 → 33, and any creature that is a quarter of its area's hostiles then sets the area's
  level itself, so no buff can ever make it elite there. An area with chests but no hostiles needs
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

## Creatures and bosses (Phase 4)

```
bst_install (every spawn) ─► loot_champion.nss   maybe promote to a champion
bst_ondeath (PC-credited kill) ─► loot_ondeath.nss   roll the drop onto the corpse
                                   └─ Loot_Roll / Loot_GiveNamed (loot_inc) ─► party roll on pickup
```

All numbers live in `loot/sources.json` `"creatures"`; `bin/loot-sim.py --creatures --write`
regenerates the review report **`CLAUDE-loot-creature-audit.md`** (the gate only *notes* when it
is stale).

- **Classes.** `boss` = in the Roll of the Fallen registry (`LootD_IsBoss`, generated from the
  `brd_db.nss` block) - 100%, the `boss` profile (2 Epic+ rolls, +1 at CR >= `extra_roll_cr`), plus a
  separate named-pool roll at `named_chance`. `elite` = a champion, `elite_include`, or **CR loot
  level >= area loot level + `elite_margin`** (5) unless `elite_exclude` - 25%. `normal` - 4%.
  `exclude` never drops. Normal and elite need a hostile faction (`LootD_IsHostileFaction`, the same
  rule as the area levels); bosses drop whatever their faction (six are placed as Commoners).
- **Area loot level = the median hostile CR** (`levels.json` `area_percentile` 50). The 75th
  percentile was tried and reverted: it barely moved towns, and a creature that is a quarter of its
  area's hostiles then sets the level itself, so no buff can make it elite there.
- **The drop rolls at the creature's own CR level** (a boss can be pinned by
  `levels.json` `boss_overrides`), is delivered to the corpse **droppable** (`Loot_MarkCorpseLoot`;
  Jasperre's `DeleteAllThings` destroys a corpse's non-droppable items), staggered 0.1 s apart from
  the module object so a boss never builds 3-4 items in one frame. Python mirror:
  `loot_model.creature_drop`.
- **CR is the stored `ChallengeRating`**, and the toolset recomputes it only in the Properties
  dialog. It is checked with nwn_manager's `bin/nwn-cr` (see [CLAUDE-creature-cr.md](CLAUDE-creature-cr.md));
  a creature made stronger outside the toolset must get its CR resynced or it will not class as elite.
- **Making a named "Elite" truly elite:** `bin/buff-named-elites.py` - real stat and gear buffs
  (non-droppable new gear in empty slots, item Cost from `loot_model.CostModel`), lockstep across
  blueprint + placements, then `nwn-cr --resync`. Never elite-by-name (admin, 2026-11-06). Done:
  Carrok Elite Guard; Dol Guldur City (12 regular `dgbowman`, 5 elite Bow Men, General, Captain).

### Champions

- **Who:** a normal creature in a hostile faction - never a boss, natural elite, summon/henchman,
  plot/immortal, `exclude`, `LOOT_NONE` or `LOOT_NO_CHAMP`.
- **How often:** `champions.chance` per mille (5%) in an area with no natural elites, falling linearly
  with the area's natural-elite share to `min_chance` (1%) at `density_cap` (25%). Precomputed per
  area (`loot_model.area_champion_chances` -> `LootD_AreaChampion`), cached on the area as
  `LOOT_AREA_CHAMP`. Champions are runtime only, so they never move an area's median.
- **What:** "Elite " name prefix, a red glow, +100% max HP (`NWNX_Object_SetMaxHitPoints`), +4 AC
  and saves (supernatural, tagged `LOOT_CHAMP`), +4 attack / +2 damage through the bonus pool
  (`BPOOL_SRC_CHAMP` - never a raw `EffectAttackIncrease`, `check_bonus_pool` enforces it).
- **CR follows the power, not the other way round:** the new CR is the stored CR plus the toolset
  formula's hit-point term for the added HP (0.2 x HD x walk/PC-walk / average class HP x race
  CRModifier, read from the 2DAs at spawn), set with `NWNX_Creature_SetChallengeRating`. Kill XP
  and the drop's loot level follow. Sizing the buff *to* a CR target was rejected: reaching an
  area's elite bar takes a median x4 and up to x20+ HP.
- **Bestiary:** a champion counts under its base creature (same canonical resref) and is tallied in
  `kills.champ_kills` (migrated by `Bst_InitDb`); messages and the server-first record use the base
  name (`LOOT_CHAMP_NAME`) and base CR (`LOOT_CHAMP_BASECR`). The book shows "Champions:N"; the wiki
  creature page adds a Champions column.

## Loot Lab

Rest menu → Admin Options → **[Admin] Loot Lab** (`emotewand.dlg` Entry 19,
`lootlab_*.nss`). It can:

- set the loot level (±1 / ±10) and cycle the rarity floor (tokens 6450 / 6451);
- roll 1 or 10 items into your pack;
- restock the nearest container: a loot container gets one real fill of its own profile at its
  own loot level (and reports the area's level); anything else gets 5 lab-level items;
- dump every rolled item's stamps with its engine value against its budget;
- **force creature drops on my kills** (token 6452, PC local `LOOT_FORCE_DROPS`): every kill you help
  make drops at 100% and prints `LOOT: <name> class=.. cr=.. lvl=.. area=.. -> n item(s)`;
- **make the nearest hostile creature a champion** (skips the chance roll, keeps every eligibility rule).

Phases 5 and 7 add "grant a gem" and "grant a Shard of Fate" here.

## Value budgets: why they exceed the forge caps

The budgets are anchored to obtainable gear, not to the forge caps (admin decision,
2026-11-05). `bin/loot-sim.py --calibrate` prints the gear percentiles. A roll worth more
than a forge's cap simply cannot be enchanted further there, exactly like the existing
top gear (`modifyitem` refuses any change that would push past the cap). No forge rule
changed.
