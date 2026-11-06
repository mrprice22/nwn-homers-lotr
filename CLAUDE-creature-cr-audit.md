# Creature CR drift audit

**Generated** by `python3 bin/creature-cr-audit.py --write`, from nwn_manager's `bin/nwn-cr`
(the toolset's challenge-rating formula, calibrated in `bin/nwn_wiki/cr.py` there) joined with
this module's loot levels and boss rule. Do not hand-edit. Roadmap: `lo-creature-drops`.

The toolset recomputes a creature's stored CR only when its Properties dialog is OK'd. Every
edit made outside it (scripts, the July +12-abilities pass, gear revalued by the forge rework)
leaves the stored CR stale. Stored CR drives kill XP, encounter spawn budgets, area loot
levels, the elite rule and the boss board.

## How well the formula reproduces stored CRs

| set | blueprints | exact | within 2% | within 10% | within 25% |
|---|---|---|---|---|---|
| all with every item resolved | 829 | 437 (53%) | 608 | 757 (91%) | 789 |
| CRAdjust = 0 | 477 | 297 (62%) | 361 | 426 (89%) | 447 |
| CRAdjust != 0 | 352 | 140 (40%) | 247 | 331 (94%) | 342 |

2 blueprints have an item the formula cannot price (a hak-only item); they are left out.

## Summary of a full resync (every spawned non-utility blueprint off by more than 10%)

| | count |
|---|---|
| drifted blueprints that spawn | 1 |
| ... utility NPCs (`q_`, `cbd_`, `cp_`, `dmfi_`, `ds_`), CR probably hand-set on purpose | 1 |
| ... drift driven mostly by **item value** | 0 |
| ... other | 0 |
| CR would rise / fall | 1 / 0 |
| boss board: joins / leaves | 0 / 0 |
| area loot levels that change | 0 |
| loot-class changes (slots) | none |

## Utility NPCs (likely hand-set - probably leave alone)

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| Combat Dummy | `cbd_dummy` | 1 | 444 | +44300% | hit_points | - | +0 | 1 | normal 1 -> normal 1 | `bree` |

## Drift driven by item value

None.

## Other drift (stats, levels, HP changed since the last toolset save)

None.

## Area loot levels after a full resync

None.

