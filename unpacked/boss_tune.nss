// boss_tune - the ONE place boss timing is tuned.
//
// Every boss timer in the module reads a constant from this file, so
// rebalancing is a one-line edit here plus a regenerate; no blueprint, no
// placement and no per-boss script ever carries a number of its own.
//
// Consumers:
//   se_respawn_inc.nss          respawn delay after a placed boss dies
//                               (BOSS_RESPAWN_SECONDS; ordinary creatures keep
//                               CRE_RESPAWN_SECONDS)
//   enr_inc.nss                 how long a damaged boss must stay out of
//                               combat before its enrage stacks are stripped
//                               and it is fully restored (BOSS_RESET_SECONDS)
//   bin/gen-boss-registry.py    seeds boss_registry.respawn_seconds - the
//                               Roll of the Fallen countdown and the wiki
//   tests/check_boss_registry.py  build gate: every registry row and every
//                               boss encounter instance must agree with
//                               BOSS_RESPAWN_SECONDS
//
// AFTER CHANGING BOSS_RESPAWN_SECONDS, run:
//     python3 bin/gen-boss-registry.py --write   # reseed the registry rows
//     python3 bin/retune-boss-encounters.py --apply   # encounter ResetTimes
//     python3 tests/check_boss_registry.py       # the build gate
// The gate fails the repack until all three agree, so a half-done retune
// cannot ship. Both Python tools read the constants straight out of this file
// (see BOSS_TUNE_RE in bin/boss_index.py) - there is no second copy to update.

// How long a boss stays dead before it respawns. Applies to registry bosses
// only (Roll of the Fallen / CR>60 single-instance); placed bosses get this as
// a se_respawn_inc DelayCommand, encounter bosses as the encounter ResetTime.
const int BOSS_RESPAWN_SECONDS = 1200;   // 20 minutes

// How long a boss that has been damaged and then abandoned must stay out of
// combat before enr_inc strips its enrage stacks, heals it, restocks its kit
// and sends it home. Deliberately longer than the respawn: walking away from a
// wounded boss should never be cheaper than killing it.
const int BOSS_RESET_SECONDS = 1800;     // 30 minutes

// Ordinary (non-boss) static creatures. The historical se_respawn_inc default;
// bosses branch off it, everything else in the world still uses it.
const int CRE_RESPAWN_SECONDS = 900;     // 15 minutes
