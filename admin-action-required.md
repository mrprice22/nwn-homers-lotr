# Admin actions required

_Appended by autopilot; delete entries as you complete them._

## Session summaries

## Toolset / placement actions
- [ ] **ferny-return** (2026-07-14): create waypoint tag `AP_ferny_return_1` in
  `billfernyshouse` (somewhere in the main room, clear of the door and the existing
  ambush encounter trigger) — spawn point for the `fret_impostor` ruffian in the new
  Ferny's Return quest. Until it exists the quest can be accepted but the house stands
  empty (scripts no-op gracefully; the guard's reminder line re-checks on every talk).
- [ ] **miller-other-son** (2026-07-14): create waypoint tag `AP_miller-other-son_1` in
  `tharbadbridge` (on or near the bridge road, clear of the refugee crowd) — spawn point for
  `mos2_peddler` (Tolly the Peddler), the optional signpost NPC in the new The Miller's Other
  Son quest. Scripts no-op gracefully until it exists; Han's reminder line and the peddler's
  own greeting re-run the spawn check on every talk.
- [ ] **miller-other-son** (2026-07-14): create waypoint tag `AP_miller-other-son_2` in
  `thardbadeast` (in the ruins east of the bridge, a reasonable walk from the area transition
  so the "cult camp" reads as a destination) — spawn point for `mos2_leader` (The Voice of the
  Red Eye, tag `MillerCultLeader`), the quest's finale NPC. He spawns non-hostile (talk first,
  Persuade/fight/walk-away resolutions) and only turns hostile by script.

- [ ] **riddle-game** (2026-07-14): create waypoint tag `AP_riddle-game_1` in
  `breecave` (Bree Cave — near the water's edge or a shadowy corner, clear of the
  existing spawns and the cave-mouth transition) — spawn point for `q_rid_wretch`
  (the Whispering Wretch), the weekly Riddle Game NPC. Spawned by `q_rid_spawn`
  from the area's OnEnter wrapper whenever a PC walks in; scripts no-op gracefully
  until the waypoint exists and never double-spawn. The placed Gollum boss is a
  separate blueprint and is unaffected.

## Design questions
- [ ] **unlock-more-inacessible-creature** (2026-07-13): the item's original ask ("write plan
  to incorporate the absent creatures") is done — the plan is in the Endgame Difficulty design
  brief and split into two backlog slices (`forbidden-realms-key-tier`, `tier-areas-moria-nazgul`).
  Should this umbrella be closed as implemented (like you did for
  `higher-difficulty-ceiling-revamp`), or stay open until the two slices ship? Item moved to
  under-consideration; answer and drag it back to a working lane (or close it) to resolve.
