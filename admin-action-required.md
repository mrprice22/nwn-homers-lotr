# Admin actions required

_Appended by autopilot; delete entries as you complete them._

## Session summaries

## Toolset / placement actions
- [x] **ferny-return** (2026-07-14): create waypoint tag `AP_ferny_return_1` in
  `billfernyshouse` (somewhere in the main room, clear of the door and the existing
  ambush encounter trigger) — spawn point for the `fret_impostor` ruffian in the new
  Ferny's Return quest. Until it exists the quest can be accepted but the house stands
  empty (scripts no-op gracefully; the guard's reminder line re-checks on every talk).
- [x] **miller-other-son** (2026-07-14): create waypoint tag `AP_millerotherson_1` in
  `tharbadbridge` (on or near the bridge road, clear of the refugee crowd) — spawn point for
  `mos2_peddler` (Tolly the Peddler), the optional signpost NPC in the new The Miller's Other
  Son quest. Scripts no-op gracefully until it exists; Han's reminder line and the peddler's
  own greeting re-run the spawn check on every talk.
- [x] **miller-other-son** (2026-07-14): create waypoint tag `AP_millerotherson_2` in
  `thardbadeast` (in the ruins east of the bridge, a reasonable walk from the area transition
  so the "cult camp" reads as a destination) — spawn point for `mos2_leader` (The Voice of the
  Red Eye, tag `MillerCultLeader`), the quest's finale NPC. He spawns non-hostile (talk first,
  Persuade/fight/walk-away resolutions) and only turns hostile by script.

- [x] **riddle-game** (2026-07-14): create waypoint tag `AP_riddlegame_1` in
  `breecave` (Bree Cave — near the water's edge or a shadowy corner, clear of the
  existing spawns and the cave-mouth transition) — spawn point for `q_rid_wretch`
  (the Whispering Wretch), the weekly Riddle Game NPC. Spawned by `q_rid_spawn`
  from the area's OnEnter wrapper whenever a PC walks in; scripts no-op gracefully
  until the waypoint exists and never double-spawn. The placed Gollum boss is a
  separate blueprint and is unaffected.

- [ ] **beorns-garden** (2026-07-15): create waypoint tag `AP_beornsgarden_1` in
  `beorn` (Beorn's homestead — somewhere in the open garden/meadow ground, clear of
  Grimbeorn, the Beornings and the deer, with room for a warg pack to spawn and fight) —
  spawn point for honey hive 1 (`q_brn_hive`, a CEP hollow-stump placeable). Hives are
  spawned by `q_brn_spawn` from the area OnEnter wrappers; scripts no-op gracefully until
  the waypoint exists and never double-spawn.
- [ ] **beorns-garden** (2026-07-15): create waypoint tag `AP_beornsgarden_2` in
  `carrok` (Carrok — off the road, clear of the frost-giant encounter spawn points so the
  hive fight doesn't pull giants) — spawn point for honey hive 2. Same spawner/no-op
  behavior as hive 1.
- [ ] **beorns-garden** (2026-07-15): create waypoint tag `AP_beornsgarden_3` in
  `carrokgreater` (Carrok: Greater — likewise clear of the standing encounters) — spawn
  point for honey hive 3. Same spawner/no-op behavior. Until all three waypoints exist the
  quest can be accepted but only the placed hives can be harvested (the turn-in needs all
  three, so place all of them).

- [ ] **twentieth-plot-mazarbul** (2026-07-15): create waypoint tag `AP_mazarbul20_1` in
  `chamberofrecords` (Chamber of Records Wlkwy — among the record-stones, clear of the four
  orc encounter spawns and the two exits) — spawn point for `q_maz_ghost` (Frár the
  Restless, the quest-giving dwarf shade; Plot, non-hostile). Spawned by `q_maz_spawn` from
  the area OnEnter wrapper; scripts no-op gracefully until the waypoint exists and never
  double-spawn.
- [ ] **twentieth-plot-mazarbul** (2026-07-15): create waypoint tag `AP_mazarbul20_2` in
  `chamberofrecords` (near the ghost but a few steps away, reachable on foot) — spawn point
  for crypt-seal brazier 1 (`q_maz_braz`, CEP "Brazier, Dungeon" placeable, usable). Same
  spawner/no-op behavior.
- [ ] **twentieth-plot-mazarbul** (2026-07-15): create waypoint tag `AP_mazarbul20_3` in
  `balinstomb` (Balin's Tomb — flanking the tomb, clear of the standing CR-134 encounter
  trigger so lighting a brazier doesn't pull the Mutant Terror) — spawn point for crypt-seal
  brazier 2. Same spawner/no-op behavior.
- [ ] **twentieth-plot-mazarbul** (2026-07-15): create waypoint tag `AP_mazarbul20_4` in
  `balinstomb` (the tomb's other flank, likewise clear of the encounter trigger) — spawn
  point for crypt-seal brazier 3. Until all four waypoints above exist the quest can be
  accepted but not finished (all three braziers are required), so place all of them.
- [ ] **twentieth-plot-mazarbul** (2026-07-15, *optional*): create waypoint tag
  `AP_mazarbul20_5` anywhere with fighting room (suggest the open floor of `balinstomb`) —
  a dedicated arena spot for the Wraith of the Twentieth Plot (CR 21). If you skip this one
  the wraith simply rises at whichever brazier completed the seal, which also works.
- [ ] **prestige-trainer-hub** (2026-07-15): create waypoint tag `AP_prestigehub_1` in
  `thewelloferu` (somewhere prominent near the well itself, clear of the Well-Mart, the
  Donations Chest, the guardians and the Recent Updates board) — spawn point for
  `prsg_trainer` (Halmir the Grey, Keeper of the Old Orders), the prestige-class quest
  hub NPC. Spawned by `prsg_spawn` from the area's OnEnter wrapper (`prsg_enter`);
  scripts no-op gracefully until the waypoint exists and never double-spawn. All twelve
  future prestige quests will hang their giver dialogues on this NPC.
- [ ] **harper-scout-quest** (2026-07-15): create waypoint tag `AP_harperscout_1` in
  `theprancingpo001` (The Prancing Pony ground floor — at or beside a corner table, clear
  of Barliman, the merit NPC and the door) — spawn point for `q_hrp_contact` (Della
  Heathertoes, tag `HarperContact`, the Harper cipher contact; plot, non-hostile).
  Spawned by `q_hrp_spawn` from the inn's OnEnter wrapper `q_hrp_ent1` (chains the
  previous `leash_to_area`) and re-checked when a PC accepts the errand from Halmir;
  scripts no-op gracefully until the waypoint exists and never double-spawn. Until it
  exists the errand can be accepted but not advanced. Note the quest offer also requires
  Halmir's own waypoint `AP_prestigehub_1` (entry above).

## Notes
- **2026-07-15 waypoint tag fix (no action needed):** the waypoints you placed carry
  hyphen-less tags (`AP_riddlegame_1`, `AP_millerotherson_1/2`) while the scripts
  originally looked for the hyphenated item ids (`AP_riddle-game_1`, …) — that's why the
  wretch and Tolly never spawned. All scripts/blueprints now use your placed tags, so your
  placements stand as-is; `AP_ferny_return_1` always matched. Beorn's Garden (WIP) was
  renamed ahead of time to `AP_beornsgarden_1/2/3`. Autopilot's tag convention is now
  hyphen-less going forward.

## Design questions
- [ ] **unlock-more-inacessible-creature** (2026-07-13): the item's original ask ("write plan
  to incorporate the absent creatures") is done — the plan is in the Endgame Difficulty design
  brief and split into two backlog slices (`forbidden-realms-key-tier`, `tier-areas-moria-nazgul`).
  Should this umbrella be closed as implemented (like you did for
  `higher-difficulty-ceiling-revamp`), or stay open until the two slices ship? Item moved to
  under-consideration; answer and drag it back to a working lane (or close it) to resolve.
