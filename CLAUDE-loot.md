# Rolled loot (Season 3 Loot Overhaul) — developer reference

Roadmap epic `loot-overhaul`; the design and phase plan are in
[docs.manual/Draft/Loot-Overhaul.html](docs.manual/Draft/Loot-Overhaul.html). This file
is the working reference for the code as built. Phase 2 (`lo-loot-core`) built the
engine; phase 3 (`rng-based-gear-diablo-world-of-warcraft-style`) put it in every chest and
container. Phases 4 (creature and boss drops), 5 (sockets and gems), 6 (the wishlist) and 7 (the
Shard of Fate) reached dev together in one `repack-homers-lotr-clean` (2026-11-06). Phase 8 (the
wiki pages) is all that is left of the epic.

## One data source, three readers

```
loot/*.json ──► bin/loot_model.py ──┬─► bin/gen-loot-tables.py ─► unpacked/loot_data_inc.nss ─► loot_inc.nss (game)
                                    │                           ├► unpacked/socket_data_inc.nss ─► gem_inc.nss (Phase 5)
                                    │                           └► unpacked/sgem_*.uti.json (75 gem blueprints)
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
| `loot/gems.json` | **socket gems** (Phase 5): families (affixes they merge into, ladder, steps per tier, icon), the five cuts, level bands, boss floor |
| `loot/sockets.json` | socket counts for **existing** (not rolled) items: default / two-socket cost / overrides / excludes, extra and ignored base rows, schema `version` |
| `loot/tokens.json` | the **Shard of Fate** (Phase 7): blueprint, boss drop chance, bonus-roll prompt timeout, lockout, profile |
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

The affix steps are shared with the Phase 7 reforge: `Loot_RollAffixes` (pick + budget, into the
`LW_*` work list; mirror `roll_affixes`) and `Loot_ApplyWork` (apply with the self-check, name it).
Their extra parameters (`sBlock`, `nMaxNew`, `oTemplate`/`nTotalCap`) default to "a fresh roll",
and the split was checked byte-identical against a seeded `roll()` before and after.

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
- **Socket gems** in chests (admin, 2026-11-05): each container profile's `socket_gem_chance`
  (per mille) adds one gem after the consumables - see "Sockets and gems (Phase 5)".
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

## Sockets and gems (Phase 5)

Roadmap `Socket-system-for-weapons` (Methonash). Runtime `gem_inc.nss`; Python mirror
`loot_model.gem_merge` / `item_sockets` / `gem_drop` (**change one, change the other**);
`python3 bin/loot-sim.py --gems` prints sockets by rarity, gems per source and level, and the
full merge table.

```
loot/gems.json + sockets.json ─► gen-loot-tables.py --apply ─► socket_data_inc.nss + sgem_<fam>_<tier>.uti.json
Loot_Roll ─► SOCKET_ROLLED / SOCKET_MAX by rarity            (loot_inc; rarity.json "sockets")
Loot_FillContainer / loot_ondeath ─► Loot_DropSocketGem ─► gem_drop.nss ─► Gem_Drop
dmfi_activate (tag sgem_*) ─► gem_activate.nss ─► Gem_Socket ─► Gem_Apply (the merge)
mod_cliententer (10.5 s) ─► gem_login ─► Gem_BeginScan ─► gem_scan_step (8 items/step) ─► Gem_Reconcile
```

- **Separate include on purpose.** `socket_data_inc` is read only by `gem_inc`; loot_inc reaches
  the gem tables through `ExecuteScript("gem_drop")`, so the 30 chest wrappers never carry them.
  Both are includes: a change needs `repack-homers-lotr-clean`.
- **Gem = blueprint `sgem_<family>_<tier>`**, Tag == ResRef, base 24 (miscsmall: non-equippable,
  stack 1), `PaletteID` 57, Unique Power **iprp_spells 329** (targeted ACTIVATE_ITEM - 335 is Self
  Only and cannot target an item). The blueprints are **generated**; the gate compares their
  meaningful fields, not bytes, so a toolset save does not trip it. Names are coloured by tier at
  creation (`Gem_Create`), so only gems made by script are coloured.
- **The merge (admin 2026-11-06):** a gem raises its family's property by `steps[tier]` rungs of the
  family ladder, or adds it at rung `steps-1`. The **last rung is the cap** - 2d10 damage
  (`iprp_damagecost` row 13) and +16 enhancement/attack are hard gate invariants
  (`GEM_CAP_DAMAGE_ROW`, `GEM_CAP_HIT`). The damage ladder skips flat +5 (`+1..+4, 1d6 .. 2d10`).
  A value **off** the ladder (+5, 1d4, 2d4, 1d12, +6..) is placed at the highest rung no stronger by
  **average damage** (`LootD_DmgPower`, from `hak_2da/iprp_damagecost.2da`), and the result must be
  stronger - so +5 steps to 1d10. Refusals change nothing and keep the gem.
- **Fit:** a family fits an item whose category (`LootD_SockBaseCat`: bases.json + `extra_bases`)
  is in one of its affixes' `cats`; with no existing property, the first affix whose cats include the
  category is created (Keenstone: enhancement on melee/caster, attack bonus on ranged).
- **Item locals:** `SOCKET_MAX/FILLED/VER/ROLLED`, `SOCKET_<n>_GEM`, `SOCKET_BASEDESC`, and
  `GEM_P_N` / `GEM_P_<i>` / `GEM_P_<i>_OWN` = `ForgePropSig` of every property a gem touched and
  whether a gem created it. The description is always rebuilt from `SOCKET_BASEDESC` + the socket
  line (`Loot_SetSocketDesc`), never appended.
- **Forge interaction** (`forge_inc` `ForgePropInSet(ip, nSel, oItem)`): a gem-**created** property
  is not COUNTED (sockets are separate from forge slots); no gem-touched property is REMOVABLE
  (staged disenchant cannot strike it); PRICED is unchanged (gem value counts against a forge's value
  ceiling). `modifyitem` refuses an enchant that would rework a gem-touched property
  (`ForgeMatchesGemProp`). Every `ForgePropInSet` call that enumerates an item **must pass oItem**.
- **Phase 7 note:** when a gem raises a rolled affix, `Gem_TrackProp` removes that property from
  `LOOT_AFX_*`, so the reforge (which strips exactly `LOOT_AFX_*`) can never take a gem.
- **Existing gear** (`Gem_SocketMax`): a rolled item keeps `SOCKET_ROLLED`; otherwise a socketable
  base, not Plot / Cursed / stacked, gets `default` (1), or the `LootD_SockList` exception (the
  two-socket tier = blueprint Cost >= `two_cost`, overrides, excludes - packed by first character).
  Bump `sockets.json` `version` to make the login pass re-reconcile everything (it only ever adds).
  The gate fails on a wearable single-stack base row a module item uses that is in neither
  `bases.json`, `extra_bases` nor `ignored_bases`.
- **Drops:** tier = a rarity roll at max(source floor, level band floor), capped at the band
  ceiling; family by weight. Chests: `socket_gem_chance`. Creatures: class `gem_chance`, rolled
  independently of the gear chance; a boss's gem has `boss_floor`. The Loot Lab force-drops switch
  forces the gem too.

## Wishlist (Phase 6)

Roadmap `lo-wishlist`. Config: `loot/sources.json` `"wishlist"` (`picks` 5, `chance` 400 per
mille, `focus_weight`). Python mirror: `loot_model.wish_candidates` / `wish_pick` and
`roll(..., wish=...)` (**change one, change the other**). `python3 bin/loot-sim.py --wishlist 1,13`
or `--auto-feats 51 --caster` prints the share of the candidate bases per profile, with and without.

```
rest menu "Loot wishlist..." (emotewand R176) ─► lw_open ─► lw_nui (window) ─► lw_evt (clicks)
                                                                   └─ loot_db Loot_WishAdd/Remove/Clear/SetAuto
Loot_Roll step 3 ─► Loot_WishPick(oBeneficiary, profile) ─► base row, else the normal category pick
```

- **Storage:** `lootdb` `loot_wishlist(uuid, base)`, keyed by `GetObjectUUID`; the row
  `base = -1` means Auto off. Cached on the PC as `LOOT_WISH` (`"|1|13|"`), loaded on first use and
  rewritten by every change, so a roll never queries SQLite. DDL in `Loot_InitDb` (onmoduleload).
- **The pick:** only for a PC beneficiary, at `LOOTD_WISH_CHANCE`; candidates are the picks
  (uniform), else the Auto list; each must fit the profile (`LootD_ProfileCatWeight` of its
  `LootD_BaseCat` > 0 and `LootD_ProfileBaseOk`). Nothing fits = the normal pick. Only the base
  item is steered - never the rarity, affixes, budget or the named-pool branch.
- **Auto** (`Loot_AutoList`, cached as `LOOT_AUTO` per `GetHitDice`, tier in `LOOT_AUTO_TIER`):
  tier 1 = melee/ranged bases whose weapon-focus family feats the PC holds
  (`LootD_BaseFocusFeats`, `focus_weight` per feat); tier 2 when tier 1 is empty = melee/ranged/caster
  bases the PC is proficient with (any of `LootD_BaseReqFeats`, or none needed) at their base
  weight, the magic staff only when spellcasting classes (`LootD_ClassCaster`) hold at least half
  the PC's levels (admin 2026-11-06: a wizard leans to dagger/club/crossbows/quarterstaff/magic
  staff). The feat and caster columns come from `baseitems.2da` / `classes.2da` via
  `--refresh-costs` into `_costs.json`; the gate fails when they are missing.
- **Beneficiary:** the chest opener (`LootChest_Beneficiary`), or for a corpse a random PC
  contributor **in the corpse's area** (`bst_ondeath` -> `LOOT_BENEF`; nobody present = unset =
  unbiased). Loot Lab rolls are for the admin, so lab "Roll 10" shows the bias.
- **Known gap:** the prod -> dev vault sync copies `.bic` files, not `lootdb`, so wishlists reset on dev.

## Shard of Fate (Phase 7)

Roadmap `lo-fate-token`. Config: `loot/tokens.json` `"fate"` -> `LOOTD_FATE_*`. Blueprint
`lo_fate_shard` (Tag == ResRef, base 29 miscmedium, **Plot** so no store buys it, no properties,
icon 093). Python mirror: `loot_model.reforge` / `creature_drop` (**change one, change the other**);
`python3 bin/loot-sim.py --reforge 40,3` prints the boss Shard rate and N reforges of a real roll.
The gate (`validate_tokens`) checks the blueprint, the ranges, and that `merit_redeem.nss`
`MERIT_FATE_SHARD` names the same resref.

```
anvil: forge_fate_can (gate) ─► confirm entry D5 ─► forge_fate_go ─► Loot_Reforge (loot_inc)
boss death: loot_ondeath ─► Loot_DropShard (10%, PL_ALWAYS)    ─► corpse ─► Need/Greed
                        └─► LootO_FateOffers ─► fate_open ─► fate_inc NUI ─► fate_evt ─► Fate_Spend
merit shop: reward 305 ─► Merit_GrantInstant (deliver, then charge)
```

- **Reforge** (`Loot_Reforge`, transactional like the staged disenchant). It refuses a non-rolled
  item, a `LOOT_NAMED` one, or a base that is no longer a loot base. The new set is chosen on a
  scratch forge blank carrying only the **kept** properties (anything whose `ForgePropSig` is not in
  `LOOT_AFX_*`: forged enchantments, gem properties). Kept properties go into `sBlock`
  (`Loot_TypeSubKey`, with sub 65535 normalised to 0), so no affix duplicates one. The real item is
  touched only once a set with at least one upside fits. Then `Loot_StripAfx` removes each
  `LOOT_AFX_*` signature once, `Loot_ApplyWork(..., bStamp=TRUE)` adds the new set and re-stamps
  `LOOT_AFX_*` **from the properties it built**, and `LOOT_FATE_N` counts reforges. Nothing is read
  back after a `RemoveItemProperty`. Level, rarity, base, look, sockets, gems and description are
  unchanged.
- **Reforge bounds** (every item-changing path bounds itself):
  - the affix-only value fits the rarity budget at `LOOT_LVL`, the same budget the original roll had;
  - the whole item stays at or under max(its value now, the forge's `MODIFY_MAX`);
  - counted enchantments stay at or under max(its count now, `MODIFY_MAX_PROPS`).

  The Shard is spent **only after** a committed reforge. `forge_fate_go` also clears the staged
  disenchant plan, because its indices point at the old properties.
- **Dialogs:** the reply, the D5 confirm and its two answers come from
  `bin/inject_forge_disenchant.py`, appended in the injected tail. Never hand-add them, because
  `migrate()` truncates that tail on every re-injection.
- **Boss bonus roll:** after the boss's drops, every PC contributor (`bst_ctrb_*`) in the corpse's
  area who holds a Shard and is not locked out gets the `fate_inc` window (`LOOTD_FATE_TIMEOUT`
  seconds, a nonce per offer, so a newer boss replaces an open prompt and a stale tick does
  nothing). **Spend** re-checks the nonce, the lockout and that the Shard is still carried. It rolls
  ONE `Loot_Roll` from `LOOTD_FATE_PROFILE` at the boss's loot level and profile floor into the
  pack, and only then spends the Shard and writes the lockout, so a failed roll keeps the Shard.
- **Lockout:** `lootdb` `loot_fate_lockout(uuid, boss, at)`, one row per character per boss resref,
  unix time. Free again `LOOTD_FATE_LOCKOUT` seconds later (rolling 24 h, admin 2026-11-06). Same
  vault-sync gap as the wishlist: the table does not come across to dev.
- **Drop:** `Loot_DropShard` sets `PL_ALWAYS`. `inc_partyloot` `PL_OnItemAcquired` rolls such an
  item below the party's gp threshold (admin 2026-11-06: a Shard always goes to Need/Greed).
- **Telemetry:** every reforge is logged to `loot_roll_log` with source `fate`, at any rarity.
- **Test realms:** the Well of Eru Donations Chest cheat stock (dev and test roles only,
  `SP_CHEAT_CHEST`) keeps **3** Shards of Fate, topped back up on every close - an `EXTRAS` row with
  `copies` 3 in `bin/gen-cheat-chest.py`. Loot Lab's "Grant me a Shard of Fate" is the admin route.

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
- **make the nearest hostile creature a champion** (skips the chance roll, keeps every eligibility rule);
- **grant a random socket gem** / **one gem of every family**, at the rarity floor as the gem's tier
  (`lootlab_gem1` / `lootlab_gemall`, Phase 5); the dump also prints sockets and gem-touched properties;
- **show my loot wishlist and Auto weights** (`lootlab_wish`, Phase 6): the stored picks, the Auto
  tier and list, and the candidates a roll for you draws from.

- **grant me a Shard of Fate** (`lootlab_fate`) and **clear my Shard of Fate lockouts**
  (`lootlab_fateclr`, Phase 7), so the boss bonus roll can be tested more than once a day. The
  force-drops switch forces a boss's Shard too, and the dump shows how often an item was reforged.

## Value budgets: why they exceed the forge caps

The budgets are anchored to obtainable gear, not to the forge caps (admin decision,
2026-11-05). `bin/loot-sim.py --calibrate` prints the gear percentiles. A roll worth more
than a forge's cap simply cannot be enchanted further there, exactly like the existing
top gear (`modifyitem` refuses any change that would push past the cap). No forge rule
changed.
