# Creature challenge ratings — keeping stored CRs honest

A creature's CR is the `ChallengeRating` stored in its blueprint (and copied into every placed
instance and every encounter creature-list entry that names it). **The toolset recomputes it only
when the creature's Properties dialog is OK'd.** A module save, a repack and the server never refresh
it, so every edit made outside the toolset (a bump script, a hand edit of `unpacked/`, an item revalued
by a hak cost-table change) leaves it stale. Evidence: the July `bin/bump-legendary-npcs.py` pass gave
213 creatures +12 to every ability and none of their CRs moved.

Stored CR is read live by kill XP (`LlXp_GiveKillXP`), encounter spawn budgets, the CR > 60 "boss"
rule (`gen-boss-registry.py`, `cleanup.nss`, the bestiary's server-first), area loot levels and the
Loot Overhaul elite rule. A stale CR is wrong in all of them at once.

## The calculator lives in nwn_manager

`../nwn_manager/bin/nwn-cr` reproduces the toolset formula (`bin/nwn_wiki/cr.py` there documents the
terms and the calibration). On this module: **47% exact, 86% within 10%** of the stored CRs; most of
the rest is real drift.

```
../nwn_manager/bin/nwn-cr --project .                         # fit summary
../nwn_manager/bin/nwn-cr --project . gntfrost003             # term-by-term breakdown
../nwn_manager/bin/nwn-cr --project . --resync a,b [--apply]  # write blueprint + placements + encounter caches
```

Things the formula taught us, worth knowing before you buff anything:

- **Only equipped gear counts**, each item once whatever its stack (one arrow, not 99), and creature
  slots (hide, claws) not at all. Regeneration on a hide is power without CR.
- **Embedded items count.** A placed instance, and a blueprint baked from one (the `_2` boss
  blueprints), stores whole item structs with their own `Cost`.
- **HP is the main lever, and a weak one for martial classes:** the HP term is base HP / average class
  HP, so a big-hit-die creature needs a lot of HP per CR point (about 0.04 CR per HP at HD 40).
- **`CRAdjust` is added at the end.** The module uses it widely (350 blueprints, up to ±125); use it
  only to bring a creature level with neighbours that already carry it, on top of a real buff.
- **Item Cost is honest when computed:** `loot_model.CostModel` reproduces the toolset's item price
  (the flail it was checked on: 61,081 vs 61,080).

## The module side

- **`bin/creature-cr-audit.py --write`** regenerates **`CLAUDE-creature-cr-audit.md`**: every spawned
  blueprint whose stored CR is off by more than 10%, and what a resync would change here (loot class,
  area levels, the boss board, XP). Utility NPCs (`q_`, `cbd_`, `cp_`, `dmfi_`, `ds_`) are listed
  separately: their CR is usually hand-set on purpose.
- **`bin/buff-named-elites.py`** is the pattern for making a creature genuinely stronger: a package of
  stats, `hp_set`, new items (non-droppable in empty slots, or private copies of shared gear),
  lockstep across blueprint + placements, an `ELITE_BUFF_V` marker for idempotence, then
  `nwn-cr --resync` and `file-palette-orphans.py --apply`.
- **After any resync:** `gen-boss-registry.py` (dry run first - a creature crossing CR 60 can join or
  leave the board), `gen-area-loot-levels.py --apply`, `gen-loot-tables.py --apply`, the two audits,
  and the gates (`check_divergent_creatures`, `check_boss_registry`, `check_loot_tables`).
- **Runtime champions** raise their CR in game with the formula's HP term
  (`loot_champion.nss`, `NWNX_Creature_SetChallengeRating`); see [CLAUDE-loot.md](CLAUDE-loot.md).
