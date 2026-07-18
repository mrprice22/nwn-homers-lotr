# Admin actions required

_Appended by autopilot; delete entries as you complete them._

## Session summaries

## Toolset / placement actions

> ⚠️ **Placement priority — these unblock quests that are currently marked `implemented`
> but are INVISIBLE in-game until the waypoint exists (the giver NPC is script-spawned at
> the waypoint).** Place in this order for the most unblocking per placement:
>
> 1. **`AP_prestigehub_1` in `thewelloferu`** — ⚠️ highest leverage: spawns Halmir the
>    Grey, the prestige-class hub. Unblocks the **entire prestige quest line (~12 items)**
>    AND gates the offers for harper-scout and knight-westernesse. Place this first.
> 2. **`AP_harperscout_1` in `theprancingpo001`** — harper-scout-quest (also needs #1).
> 3. **`AP_knightwest_1` in `thepelennorfield`** — knight-westernesse-quest (also needs #1).
> 4. **`AP_mazarbul20_1..4`** (`chamberofrecords` / `balinstomb`) — twentieth-plot-mazarbul
>    (can't even be accepted without `_1`; needs all four to finish; `_5` optional).
> 5. **`AP_beornsgarden_1/2/3`** (`beorn` / `carrok` / `carrokgreater`) — beorns-garden.
>
> Full per-waypoint detail (suggested spot + purpose) is in the entries below.

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

- [ ] **knight-westernesse-quest** (2026-07-16): create waypoint tag `AP_knightwest_1` in
  `thepelennorfield` (The Pelennor Fields — somewhere open and reachable, suggest near the
  road or the Rammas side of the field, clear of the Rohirrim encounter spawns) — spawn
  point for `q_kwn_stone` (the Banner-Stone of the Rammas, tag `kwn_bannerstone`; plot,
  usable placeable, flag appearance). Spawned by `q_kwn_spawn` from the field's OnEnter
  wrapper `q_kwn_ent1` (chains the previous `d_cleartrash`) and re-checked when the
  proving is accepted and when the Gate Captain releases the standard; scripts no-op
  gracefully until the waypoint exists and never double-spawn. Until it exists the quest
  can be advanced to stage 4 (standard released) but not finished. The quest's NPCs are
  all existing placed guardsmen at `minastirithgates` (no waypoint needed for them); the
  quest offer also requires Halmir's own waypoint `AP_prestigehub_1` (entry above).

- [ ] **concerning-hobbits** (2026-07-17): create waypoint tag `AP_concerninghobbits_1` in
  `shirehobbiton001` (Hobbiton — somewhere sensible near the village green / the Ivy Bush,
  clear of the existing hobbit NPCs and Gandalf) — spawn point for `q_hob_odo` (Odo Proudfoot,
  the genealogist quiz-giver). Spawned by `q_hob_spawn` from the area OnEnter wrapper
  `q_hob_enter` whenever a PC enters; scripts no-op gracefully until the waypoint exists and
  never double-spawn. Until placed, the "Concerning Hobbits" daily quiz is invisible in-game.
  <!-- Tag is hyphen-less and byte-for-byte identical to the GetWaypointByTag literal in
       q_hob_spawn.nss: AP_concerninghobbits_1 -->

- [ ] **pass-the-pass** (2026-07-17): create waypoint tag `AP_passthepass_1` in
  `foothillsofthemi` (Foothills of the Misty Mountains — at the western foot of the pass,
  somewhere sensible on the road/entrance side, clear of the area transitions) — spawn point
  for `q_pass_capt` (Baldor the Caravan-Master, the quest giver; plot/immortal commoner).
  Spawned by `q_pass_spawn` from the shared OnEnter wrapper `q_pass_enter` (which preserves
  the area's original `d_cleartrash`) whenever a PC enters; no-ops gracefully until placed.
  Until placed, the "Pass the Pass" daily escort is invisible in-game.
  <!-- hyphen-less, byte-for-byte identical to the GetWaypointByTag literal in
       q_pass_spawn.nss: AP_passthepass_1 -->
- [ ] **pass-the-pass** (2026-07-17): create waypoint tag `AP_passthepass_2` in
  `mistymountainsa` (The Misty Mountains, first/mid pass area — on the through-route the PC
  walks east, with room for a warband + a giant to spawn and fight, clear of the standing
  giant encounters so the ambush doesn't pull them) — spawn point for the difficulty-scaled
  ambush (`QPASS_SpawnAmbush` in `q_pass_inc.nss`). No-ops gracefully until placed (the quest
  is still completable without it — no ambush, just walk across).
  <!-- literal in q_pass_inc.nss: AP_passthepass_2 -->
- [ ] **pass-the-pass** (2026-07-17): create waypoint tag `AP_passthepass_3` in
  `mistymountainsb` (The Misty Mountains, eastern waystation side — near the eastern
  transition, a sensible "far side" spot) — spawn point for `q_pass_qm` (Wilrun the
  Quartermaster, the turn-in NPC; plot/immortal commoner). Same spawner/no-op behavior as
  `AP_passthepass_1`. Until placed, the escort can be accepted but not turned in for pay, so
  place `_1` and `_3` together (`_2` is optional flavour/danger).
  <!-- literal in q_pass_spawn.nss: AP_passthepass_3 -->

- [ ] **fighter-line-early** (2026-07-17): create waypoint tag `AP_fighterlineearly_1` in
  `theprancingpo001` (The Prancing Pony ground floor — at or beside a corner table, clear of
  Barliman, the merit NPC, the Harper contact spot and the door) — spawn point for
  `q_ftr_hallas` (Hallas the Shieldwarden, the Fighter class-line I giver; plot/immortal
  human veteran). Spawned by `q_ftr_spawn` from the inn's OnEnter wrapper `q_ftr_enter`
  (which chains the existing `q_hrp_ent1` — leash + Harper contact); scripts no-op gracefully
  until the waypoint exists and never double-spawn. Until placed, "The Unbroken Shield"
  (Fighter line I, nodes L1/8/15) is invisible in-game. Fighter-only offer; non-fighters get
  a flavour greeting.
  <!-- Tag is hyphen-less and byte-for-byte identical to the GetWaypointByTag literal in
       q_ftr_inc.nss / q_ftr_spawn.nss: AP_fighterlineearly_1 -->

- [ ] **rogue-line-early** (2026-07-17): create waypoint tag `AP_roguelineearly_1` in
  `theprancingpo001` (The Prancing Pony ground floor — in or beside a doorway/shadowed corner,
  clear of Barliman, the merit NPC, the Harper contact spot, Hallas's corner and the door) —
  spawn point for `q_rog_fenn` (Fenn the Shade, the Rogue class-line I giver; plot/immortal
  hooded rogue). Spawned by `q_rog_spawn` from the inn's OnEnter wrapper `q_rog_enter` (which
  chains the fighter-line wrapper `q_ftr_enter`, itself chaining `q_hrp_ent1` — leash + Harper
  contact — and Hallas's spawn); scripts no-op gracefully until the waypoint exists and never
  double-spawn. Until placed, "The Long Shadow" (Rogue line I, nodes L1/8/15) is invisible
  in-game. Rogue-only offer; non-rogues get a flavour greeting.
  <!-- Tag is hyphen-less and byte-for-byte identical to the GetWaypointByTag literal in
       q_rog_inc.nss / q_rog_spawn.nss: AP_roguelineearly_1 -->

- [ ] **blackguard-quest** (2026-07-17): _conditional, verify-then-maybe-fix (no new placement)._
  The Blackguard fall-rite reuses the existing torture-rack in `baraddurkeep` (instance 94 of
  `plc_torture1`, retagged `BkgFallAltar`, `Static:0` + `OnUsed q_bkg_altar`) — the same
  retag shape as the shipped Red-Dragon-Disciple anvil and Divine-Champion altar. If the CEP
  `plc_torture1` base is not useable-by-default, the rack won't be clickable and the quest
  can't progress. **Verify in-game that the rack is clickable;** if not, add a single
  `Useable: {type:byte, value:1}` field to that instance (the same one-line fix would then
  apply to the sibling anvil/altar retags — worth spot-checking those too). No other action
  needed — this quest adds no waypoint.

- [ ] **item-slot-tokens** (2026-07-17): _loot placement — no waypoint._ The **Rune of
  Expansion** consumable (blueprint resref `slot_token`, tag `SlotToken`) is fully wired and
  testable but is **not placed in any loot table yet** — deliberately, because drop-source and
  rarity are your taste. Decide **which boss(es) drop it and at what rarity**, then add
  `slot_token` to their loot via the toolset / the module's loot system. To test the mechanic
  meanwhile: DM-spawn `slot_token`, activate it, target an item in your pack, then work that
  item at a forge — it should allow one extra enchantment slot per rune bound (up to 3).
  The hard ceiling is **`FORGE_TOKEN_MAX_SLOTS = 3`** in `unpacked/forge_inc.nss` — retune
  there if +3 is too generous/stingy (a fully-runed item at a top-tier forge can reach 10
  enchantments). No CR>60 boss was modified.

## Notes
- **2026-07-15 waypoint tag fix (no action needed):** the waypoints you placed carry
  hyphen-less tags (`AP_riddlegame_1`, `AP_millerotherson_1/2`) while the scripts
  originally looked for the hyphenated item ids (`AP_riddle-game_1`, …) — that's why the
  wretch and Tolly never spawned. All scripts/blueprints now use your placed tags, so your
  placements stand as-is; `AP_ferny_return_1` always matched. Beorn's Garden (WIP) was
  renamed ahead of time to `AP_beornsgarden_1/2/3`. Autopilot's tag convention is now
  hyphen-less going forward.

## Design questions
- [ ] **concerning-hobbits** (2026-07-17): the original idea called for the reward to be
  **Bag End housing access** via an owner-check workaround (single shared Bag End interior,
  `OnEnter` kicks non-owners) rather than instancing. That is design-sensitive and was NOT
  wired — it needs your calls: which door/interior gates the reward (`bagend001` vs
  `shirebilbohouse` back room / FancyDoor), whether winning grants a persistent housing
  entry (and in which table — the player-houses `housing:` system, or a bespoke campaign
  flag), and the owner-check/eviction semantics for a shared interior. The quest **ships
  now with a concrete gold/XP/pipe-weed reward instead** (working, waypoint-gated). If you
  want the housing unlock, decide the above and it can be added as a follow-up win-hook in
  `q_hob_inc.nss` (`QHOB_PayOut`). Answer here; no roadmap reactivation needed — the quiz is
  already shipped.
- [ ] **unlock-more-inacessible-creature** (2026-07-13): the item's original ask ("write plan
  to incorporate the absent creatures") is done — the plan is in the Endgame Difficulty design
  brief and split into two backlog slices (`forbidden-realms-key-tier`, `tier-areas-moria-nazgul`).
  Should this umbrella be closed as implemented (like you did for
  `higher-difficulty-ceiling-revamp`), or stay open until the two slices ship? Item moved to
  under-consideration; answer and drag it back to a working lane (or close it) to resolve.
