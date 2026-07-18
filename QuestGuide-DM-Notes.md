# Quest Guide — DM / admin notes

Internal companion to [`docs.manual/QuestGuide.html`](docs.manual/QuestGuide.html), which is
**published to the player-facing wiki**. Anything that names a script, blueprint, dialogue file,
campaign DB, tag, waypoint, area resref, roadmap item id, or an open bug belongs **here**, not
there.

## Conventions

Two files, one split:

- **`docs.manual/QuestGuide.html` (public)** — what a player needs: the quest's name, who gives it,
  where, what you do, what you get. Quest cards carry only `Working` or `In Development` badges.
  Never put a `dm-note`, an `AP_*` waypoint tag, a script resref, a roadmap id, or an "admin action
  required" line on this page — and never badge a quest as "needs waypoint"; placement debt is
  tracked in the roadmap item's `manual_steps` field, not in player docs.
- **`QuestGuide-DM-Notes.md` (this file)** — the implementation half. Section order and quest names
  mirror the public page so the two can be read side by side.

Both files should be updated in the same commit whenever a quest ships or changes. See step 3b of
[CLAUDE-autopilot.md](CLAUDE-autopilot.md).

---

## Quests

### Bill Ferny's Ring

- **Journal tag:** `Ferny's Ring`
- **Scripts / blueprints:** ambush trigger in `ferny_convo2.dlg.json`; XP 500 via `endferny1.nss`
  (give letter) or `aquirering.nss` (keep letter) — raised from 150. Items `RingofSharkey` and
  `SharkeysOrders` must be in inventory when speaking to Ferny.
- **Open points:** journal entry 2 is defined in the journal but the DLG Quest field for it points
  to the correct tag.
- **Known issue (2026-07-11):** a legacy ported-campaign plot category `p000` (struct 0, driven by
  `p000c001ondeath.nss` and the `p000q001-005` scripts) is still wired in parallel with this custom
  `Ferny's Ring` chain, so a player can end up with two journal tracks for the same plot. Tracked as
  roadmap idea `p000-duplicate-ferny-journal`.

### Ferny's Return

- **Journal tag:** `ferny_return`
- **Roadmap:** `ferny-return` (added 2026-07-14)
- **Scripts:** `q_fret_start.nss` (entry 1 + impostor spawn), `q_fret_bribe.nss`,
  `q_fret_fight.nss`, `q_fret_death.nss`, `q_fret_end.nss`. Giver branches on
  `b_guard_convo1.dlg`; impostor `fret_impostor` uses `fret_imp.dlg`.
- **Waypoints:** `AP_ferny_return_1` must be placed in `billfernyshouse`. Until then the quest can
  be accepted but the house stands empty — the guard's stage-1 reminder line re-runs the spawn check
  on every conversation, so no player state is ever stranded.
- **State:** per character in the `fret` campaign DB (stages 0–3 + outcome), not session-local ints.
- **Cross-quest:** completion stamps the prequel bonus read by `endferny1.nss` / `aquirering.nss`
  (+100 gp on either Ferny's Ring ending).
- **UAT:** scripted and built, pending in-game UAT.

### The Miller's Son

- **Journal tag:** `Bree Millers Son`
- **Scripts:** conversation `b_miller_convo1.dlg.json`; completion `at_003.nss` (now 450 XP, raised
  from 150). The shipment scene is scripted on the South Greenway.
- **State:** completion also stamps a persistent flag (campaign DB `mos2`, key `m1done`) that
  unlocks the sequel.

### The Miller's Other Son

- **Journal tag:** `bree_miller_son2`
- **Roadmap:** `miller-other-son` (added 2026-07-14)
- **Scripts:** `q_mos2_start.nss`, `q_mos2_persu.nss`, `q_mos2_fight.nss`, `q_mos2_death.nss`,
  `q_mos2_leave.nss`, `q_mos2_end1.nss`, `q_mos2_end2.nss`. Dialogues `mos2_ped.dlg`,
  `mos2_cult.dlg`.
- **Waypoints:** `AP_millerotherson_1` (peddler, `tharbadbridge`) and `AP_millerotherson_2` (cult
  leader, `thardbadeast`). Until placed the road stands empty — Han's reminder line and the
  peddler's greeting re-run the spawn check, so no player state is stranded.
- **State:** per character in the `mos2` campaign DB (stages 0–3 + outcome + the spent Persuade
  attempt). Gating on the original quest uses the session-local `millerson == 2` **or** the
  persistent `mos2/m1done` flag now stamped by `at_003.nss`; characters who finished The Miller's
  Son before this shipped can simply re-run the original (its state is session-local) to qualify.
- **UAT:** scripted and built, pending in-game UAT.

### The Last Drop at Frogmorton Inn

- **Journal tag:** `frogmorton_ale`
- **Roadmap:** `frogmorton-last-drop` (added 2026-07-14)
- **Scripts:** `q_frog_rulec.nss` (twelve rules keyed on `GetCalendarMonth()`), `q_frog_pint.nss`,
  claimant conversations `q_frog_p1`–`p5`.
- **Cooldown:** **first consumer of the shared quest-cooldown library** (`quest_cd_inc.nss` /
  the `questcddb` campaign DB): availability gated by `QCD_IsDoneToday` (resets at UTC midnight,
  survives relogs and reboots); Rigrin's come-back-tomorrow line shows real time remaining via
  `QCD_FmtSpan`. This quest doubles as UAT for the library.
- **Venue note:** the design doc placed five hobbits in `frogmorton001`, but that area has no NPCs
  and no inn interior; the quest instead reuses five existing commoner instances at the adjacent
  Whitfurrow Inn (renamed in place) with the cask lore keeping its Frogmorton origin. Zero new
  placements.
- **UAT:** scripted and built, pending in-game UAT.

### Hobbit Post

- **Journal tag:** `hobbit_post`
- **Roadmap:** `hobbit-post` (added 2026-07-14)
- **Cooldown:** second consumer of `quest_cd_inc.nss` / `questcddb`: `QCD_IsDoneToday` gates the
  offer, `QCD_Stamp` fires on payout; the speed bonus compares real-world epochs from `QCD_Now()`
  stored on the parcel (`POST_T0`), not the game clock.
- **Blueprints:** all six NPCs are existing placed instances — the postmaster and four recipients
  were renamed in place and split into dedicated blueprints (`hobbit001_2/_3`, `nw_oldman_2_2`,
  `comfemale002_5`, `commale002_4`) via `bin/split-divergent-creatures.py` so respawns keep their
  identities; the Green Dragon Inn keeper kept their name and simply gained gated parcel branches in
  `greendragon1.dlg`. Zero new placements, **no waypoints needed**.
- **Rotation:** addressee rotates on `GetCalendarDay() % 5`; 8% misdelivery chance.
- **UAT:** scripted and built, pending in-game UAT.

### Spider Silk Harvest

- **Journal tag:** `mirkwood_silk`
- **Roadmap:** `spider-silk-harvest` (added 2026-07-14)
- **Cooldown:** third consumer of `quest_cd_inc.nss` / `questcddb`; the active flag is itself a
  calendar stamp (`mirkwood_silk_acc`), so hunt state survives relogs and restarts with no state
  item.
- **Drops:** silk drops chain through the blueprint OnDeath slot (`q_silk_d1/d2/d3` on the six
  module spider blueprints), which the bestiary wrapper stores and chains at spawn; each wrapper
  re-chains the family's original reward script (`gpondeath` / `350ondeathtopart` /
  `sb_creaturekill`) — kill counts, gold and XP all still fire.
- **Giver:** existing placed Thranduil (`thranduil_2`, also a Roll-of-the-Fallen boss) — the new
  `q_silk` conversation is set identically on blueprint **and** instance, so respawns keep it. Zero
  new placements, no waypoints needed.
- **Deferred:** the Quest Ideas dynamic-pricing variant (server-wide `silk_supply` moving the price)
  is deferred to a possible v2; v1 pays a flat bounty.
- **UAT:** scripted and built, pending in-game UAT.

### The Riddle Game

- **Journal tag:** `riddle_game`
- **Roadmap:** `riddle-game` (added 2026-07-14)
- **Cooldown:** fourth consumer of `quest_cd_inc.nss` / `questcddb`, calendar-weekly via
  `QCD_IsDoneThisWeek`.
- **Blueprints:** the wretch (`q_rid_wretch`) is a plot, non-hostile clone of the Gollum blueprint —
  strongly implied to be, never named. **Spoiler: keep this off the public page.** Script-spawned at
  `AP_riddlegame_1` from the Bree Cave OnEnter wrapper (`q_rid_enter`).
- **Waypoints:** `AP_riddlegame_1` must be placed before the wretch appears (scripts no-op
  gracefully until then). The placed CR-1029 Gollum boss and its Roll-of-the-Fallen tracking are
  untouched.
- **Implementation:** one generic riddle dialogue node serves the whole bank via custom tokens
  6360–6368; the 16-riddle bank, weekly seeded selection (`%Y%W` stride walk) and reward table live
  in `q_rid_inc.nss`.
- **UAT:** scripted and built, pending in-game UAT.

### Concerning Hobbits

- **Journal tag:** `concern_hob`
- **Roadmap:** `concerning-hobbits` (added 2026-07-17)
- **Cooldown:** `quest_cd_inc.nss` / `questcddb`, calendar-daily via `QCD_IsDoneToday`.
- **Blueprints:** Odo (`q_hob_odo`) is a friendly commoner script-spawned at
  `AP_concerninghobbits_1` from the Hobbiton OnEnter wrapper (`q_hob_enter`).
- **Waypoints:** `AP_concerninghobbits_1` must be placed before Odo appears (scripts no-op
  gracefully until then).
- **Implementation:** one generic question dialogue node serves the whole bank via custom tokens
  6420–6428; the 16-question bank, season-seeded selection (`GetCalendarYear()*4 + season` stride
  walk) and reward table live in `q_hob_inc.nss`.
- **Deferred:** the "Bag End housing access" reward from the original idea is deferred to the admin
  as a design question — this ships the working quiz with a concrete gold/XP/keepsake payout.
- **UAT:** scripted and built, pending in-game UAT.

### The Unbroken Shield — Fighter line I

- **Journal tag:** `ftr_shield`
- **Roadmap:** `fighter-line-early` (added 2026-07-17)
- **State:** per character in the `fighterlinedb` campaign DB (key `ubshield_stage`, 0–3; see
  `q_ftr_inc.nss`); the stage only advances, so rewards are not farmable.
- **Gates:** `GetLevelByClass(CLASS_TYPE_FIGHTER) >= 1`; the L8/L15 gates are total character level.
- **Scripts:** `q_ftr_oath`, `q_ftr_shrd`, `q_ftr_forge`. Items `q_ftr_buckl`, `q_ftr_shard`,
  `q_ftr_blade`.
- **Blueprints:** Hallas (`q_ftr_hallas`, plot/immortal human veteran) is script-spawned by
  `q_ftr_spawn` from the Prancing Pony OnEnter wrapper `q_ftr_enter` (which chains the existing
  `q_hrp_ent1` — leash + Harper contact).
- **Waypoints:** `AP_fighterlineearly_1` must be placed in `theprancingpo001` before Hallas appears
  (scripts no-op gracefully until then).
- **Items:** reward-item properties use verified stock encodings (Enhancement / AC bonus +
  Use Limitation: Class Fighter); no CR>60 boss was touched.
- **UAT:** scripted and built, pending in-game UAT.

### The Long Shadow — Rogue line I

- **Journal tag:** `rog_shadow`
- **Roadmap:** `rogue-line-early` (added 2026-07-17)
- **State:** `roguelinedb` campaign DB (key `shadow_stage`, 0–3; see `q_rog_inc.nss`); stage only
  advances.
- **Gates:** `GetLevelByClass(CLASS_TYPE_ROGUE) >= 1`; L8/L15 are total character level.
- **Scripts:** `q_rog_oath`, `q_rog_tok`, `q_rog_rtn`. Items `q_rog_cloak`, `q_rog_token`,
  `q_rog_blade`.
- **Blueprints:** Fenn (`q_rog_fenn`, plot/immortal hooded rogue) script-spawned by `q_rog_spawn`
  from the Prancing Pony OnEnter wrapper `q_rog_enter` (which chains `q_ftr_enter` — itself chaining
  `q_hrp_ent1`'s leash + Harper contact and Hallas's spawn).
- **Waypoints:** `AP_roguelineearly_1` in `theprancingpo001`.
- **Items:** Enhancement / AC bonus + Use Limitation: Class Rogue, subtype 8. No CR>60 boss touched.
- **UAT:** scripted and built, pending in-game UAT.

### The Colour of Power — Wizard line I

- **Journal tag:** `wiz_colour`
- **Roadmap:** `wizard-line-early` (added 2026-07-17)
- **State:** `wizlinedb` campaign DB (key `colour_stage`, 0–3; see `q_wiz_inc.nss`).
- **Gates:** `GetLevelByClass(CLASS_TYPE_WIZARD) >= 1`; L8/L15 total character level.
- **Scripts:** `q_wiz_oath`, `q_wiz_tok`, `q_wiz_rtn`. Items `q_wiz_amul`, `q_wiz_tome`,
  `q_wiz_staff`.
- **Blueprints:** Findegil (`q_wiz_find`) script-spawned by `q_wiz_spawn` from the Bag End OnEnter
  wrapper `q_wiz_enter` (chains the area's existing `leash_to_area` handler).
- **Waypoints:** `AP_wizardlineearly_1` in `bagend001`.
- **Items:** Enhancement / Ability INT bonus + Use Limitation: Class Wizard, subtype 10.
- **UAT:** scripted and built, pending in-game UAT.

### The Flame of Anor — Cleric line I

- **Journal tag:** `clr_anor`
- **Roadmap:** `cleric-line-early` (added 2026-07-17)
- **State:** `clrlinedb` campaign DB (key `flame_stage`, 0–3; see `q_clr_inc.nss`).
- **Gates:** `GetLevelByClass(CLASS_TYPE_CLERIC) >= 1`; L8/L15 total character level.
- **Scripts:** `q_clr_oath`, `q_clr_tok`, `q_clr_rtn`. Items `q_clr_amul`, `q_clr_ember`,
  `q_clr_mace`.
- **Blueprints:** Aldamir (`q_clr_keep`) script-spawned by `q_clr_spawn` from the Temple of Illuvatar
  OnEnter wrapper `q_clr_enter` (chains the area's existing `leash_to_area` handler).
- **Waypoints:** `AP_clericlineearly_1` in `templeofilluvata`.
- **Items:** Enhancement / Ability WIS bonus + Use Limitation: Class Cleric, subtype 2.
- **UAT:** scripted and built, pending in-game UAT.

### The Uncrowned Path — Ranger line I

- **Journal tag:** `rng_path` (`@group 'Class Lines'`, `@order 7`)
- **Roadmap:** `ranger-line-early` (added 2026-07-18)
- **State:** `rnglinedb` campaign DB (key `path_stage`, 0–3; see `q_rng_inc.nss`).
- **Gates:** `GetLevelByClass(CLASS_TYPE_RANGER) >= 1`; L8/L15 total character level.
- **Scripts:** `q_rng_oath`, `q_rng_tok`, `q_rng_rtn`; StartingConditionals `q_rng_c_off`,
  `q_rng_c_s1w`, `q_rng_c_s1r`, `q_rng_c_s2w`, `q_rng_c_s2r`, `q_rng_c_dn`.
- **Blueprints:** Halbarad (`q_rng_keep`, conversation `q_rng_conv`) script-spawned by `q_rng_spawn`
  from the Ranger Waystation OnEnter wrapper `q_rng_enter` (chains the area's existing
  `leash_to_area` handler).
- **Waypoints:** `AP_rangerlineearly_1` in `rangerwaystation`. **Halbarad is spawn-only — the whole
  line is invisible in-game until this waypoint is placed.**
- **Items:** `q_rng_broc` (amulet, +1 DEX), `q_rng_star` (plot token), `q_rng_bow` (longbow,
  BaseItem 8, Enhancement +2 / +1 DEX). All use Use Limitation: Class Ranger, subtype 7.
- **History:** an interrupted autopilot run (commit `0b71d6908a4`) landed the scripts and the three
  UTIs only — no giver, conversation, journal category or area wiring, so nothing was reachable. The
  bow was also authored as BaseItem 6 (heavy crossbow) despite its name; corrected to 8 (longbow)
  with matching 3-part model.
- **UAT:** scripted and built, pending waypoint placement and in-game UAT.

### The Breathing of the World — Druid line I

- **Journal tag:** `drd_breath` (`@group 'Class Lines'`, `@order 8`)
- **Roadmap:** `druid-line-early` (added 2026-07-18)
- **State:** `drdlinedb` campaign DB (key `breath_stage`, 0–3; see `q_drd_inc.nss`).
- **Gates:** `GetLevelByClass(CLASS_TYPE_DRUID) >= 1`; L8/L15 total character level.
- **Scripts:** `q_drd_oath`, `q_drd_tok`, `q_drd_rtn`; StartingConditionals `q_drd_c_off`,
  `q_drd_c_s1w`, `q_drd_c_s1r`, `q_drd_c_s2w`, `q_drd_c_s2r`, `q_drd_c_dn`.
- **Blueprints:** Naldor the Green (`q_drd_keep`, Druid 30, plot/immortal, conversation `q_drd_conv`)
  script-spawned by `q_drd_spawn` from the Rhosgobel OnEnter wrapper `q_drd_enter` (chains the area's
  existing `leash_to_area` handler).
- **Waypoints:** `AP_druidlineearly_1` in `rhosgobel`. **Naldor is spawn-only — the whole line is
  invisible in-game until this waypoint is placed.**
- **Items:** `q_drd_amul` (amulet, BaseItem 19, +1 WIS), `q_drd_seed` (plot token, BaseItem 24),
  `q_drd_staf` (quarterstaff, BaseItem 45, Enhancement +2 / +1 WIS). All use Use Limitation: Class
  Druid, subtype 3 (verified against the 43 existing subtype-3 items; consistent with the confirmed
  Cleric 2 / Ranger 7 rows of `iprp_classes`).
- **Notes:** structurally cloned from the shipped `ranger-line-early` template (`q_rng_*`). Radagast
  himself is left alone — he already exists as a shopkeeper (`radagastthebrown`, `radagastshops.dlg`);
  Naldor is authored as his pupil so the two do not collide. The design brief's Tom Bombadil / Old Man
  Willow authoring is untouched and remains available for the mid/endgame chunks.
- **UAT:** scripted and built, pending waypoint placement and in-game UAT.

### Pass the Pass

- **Journal tag:** `pass_pass`
- **Roadmap:** `pass-the-pass` (added 2026-07-17)
- **Cooldown:** `quest_cd_inc.nss` / `questcddb`, calendar-daily via `QCD_IsDoneToday` /
  `QCD_Stamp`.
- **Blueprints:** giver `q_pass_capt` (Foothills) and quartermaster `q_pass_qm` (`mistymountainsb`)
  are plot/immortal commoners script-spawned from the shared OnEnter wrapper `q_pass_enter` (which
  preserves the areas' original `d_cleartrash`). Stone-Giant `q_pass_gnt` is a plot-safe CR-25 clone
  of the ordinary Misty Mountains giant.
- **Waypoints:** **three** — `AP_passthepass_1` (giver), `AP_passthepass_3` (quartermaster), and
  `AP_passthepass_2` in `mistymountainsa` (ambush). Blocked in-game until all three are placed
  (scripts no-op gracefully until then).
- **Implementation:** ambush composition scaled by difficulty in `q_pass_inc.nss`
  (`QPASS_SpawnAmbush`), using existing goblin/warg blueprints plus the new Stone-Giant clone.
  Rate-limited naturally: a PC can only accept once/day and cannot re-accept while an escort is
  active. Payout is `nDiff * 200` gp and `nDiff * 150` XP.
- **UAT:** scripted and built, pending in-game UAT.

### Sowing Discord in Bree

- **Journal tag:** `sowing_discord`
- **Roadmap:** `sowing-discord-bree` (added 2026-07-17)
- **Cooldown:** `quest_cd_inc.nss` / `questcddb`, rolling daily via `QCD_IsOnCooldown(QCD_DAY)`;
  "ready to turn in" is a second stamp key (`sowing_discord_plant`). Cooldown token 6390.
- **Placeables:** giver branches ride the existing `ferny_convo2.dlg`; plant targets are three
  existing Pony table instances retagged `SowDrop1..3` (made usable, OnUsed `q_sow_plant`) — no new
  placements, no waypoints.
- **Checks:** the stealth test is the deterministic `GetActionMode` check shared with the Quiet
  Knives dead drop. The sheriff (`q_sow_sherf`, a fighter-16 clone of the Guardian of Bree) spawns
  at the last table via `DelayCommand` and attacks only the planter (temporary enemy — no faction
  brawl).
- **Open point:** **no reputation changes yet** — faction-rep integration deliberately waits on the
  faction-scaffolding roadmap item. Logic in `q_sow_inc.nss`.
- **UAT:** scripted and built, pending in-game UAT.

### Beorn's Garden

- **Journal tag:** `beorn_garden`
- **Roadmap:** `beorns-garden` (added 2026-07-14)
- **Cooldown:** `quest_cd_inc.nss` / `questcddb`, calendar-daily via `QCD_IsDoneToday`; the active
  flag and the per-hive harvest locks are item-free calendar stamps (`beorn_garden_acc`,
  `beorn_garden_h1..3`), so state survives relogs and restarts.
- **Placeables:** hives (`q_brn_hive`, tag `HoneyHive`, CEP stump) are script-spawned by
  `q_brn_spawn` from the beorn/carrok/carrokgreater OnEnter wrappers.
- **Waypoints:** `AP_beornsgarden_1/2/3` must be placed before any hive appears (scripts no-op
  gracefully until then).
- **Creatures:** wargs (`q_brn_warg`) are quest-spawned only — no standing encounters touched — and
  their OnDeath wrapper `q_brn_wd` chains `nw_c2_default7`, staying bestiary-safe under
  `bst_install`. Grimbeorn's new conversation (`q_brn_conv`) was set on blueprint **and** placed
  instance both. Progress tokens 6370–6372.
- **UAT:** scripted and built, pending in-game UAT.

### The Twentieth Plot of Mazarbul

- **Journal tag:** `mazarbul_20`
- **Roadmap:** `twentieth-plot-mazarbul` (added 2026-07-15)
- **State:** per-character persistent in the `maz20` campaign DB (stage + `seal_1..3`), same one-off
  scheme as Ferny's Return; the reward can never be re-earned.
- **Blueprints:** Frár (`q_maz_ghost`, a Plot dwarf commoner with a permanent ghostly visage) and
  the braziers (`q_maz_braz`, CEP dungeon brazier, OnUsed `q_maz_use`) come from the
  chamberofrecords/balinstomb OnEnter wrappers (`q_maz_ent1/2`, chaining the areas' previous
  scripts).
- **Waypoints:** `AP_mazarbul20_1` (ghost) and `AP_mazarbul20_2/3/4` (braziers) must be placed
  before anything appears; optional `AP_mazarbul20_5` sets a wraith arena spot, otherwise it rises
  at the third-lit brazier.
- **Creatures:** the wraith (`q_maz_wraith`) is a detuned clone of the Witch King's wraith (CR 21 /
  420 hp), single-spawn guarded; OnDeath wrapper `q_maz_wd` chains `nw_c2_default7`
  (bestiary-safe). Elrond and his "Elrond's Request" thread were deliberately left untouched — the
  ghost is the sole quest giver. Progress token 6380.
- **UAT:** scripted and built, pending in-game UAT.

### Feeding Tharbad

- **Journal tag:** `Feeding Tharbad`
- **Scripts:** conversation `clericq.dlg.json`; completion via `at_046.nss` (now 500 XP, raised from
  200). Accept sets local variable `agreefeed = 1`.
- **Reward item:** `bookofthecora.uti.json` — *Book of the Cora* — already carries 5 properties and
  a high gold value, so it is a meaningful reward as-is.

### Elrond's Request

- **Journal tag:** `Elrond's Request`
- **Scripts:** `sc_015` checks for both items; `at_026` destroys them; `at_024` gives 2,000 XP and
  *Elrond's Writ*.
- **Fixed (2026-05-28):** the reply node in `elrondconv.dlg.json` that set the bogus tag
  `Category000` (QuestEntry 1) now sets `Elrond's Request`. This was the *quest-accept* entry —
  previously only entry 2 (completion) was ever written, so players saw no journal entry on
  accepting. A dangling `at_023` action still sets a local variable only (no quest effect);
  harmless.
- **Historical note:** the "existing journals got removed upon accepting the quest" report is a
  false diagnosis (see *Investigating player reports* below).

### Ruin of Annuminas

- **Journal tag:** `Ruin of Annuminas`
- **Fixed (2026-05-28):** the old woman's dialogue (`b_oldwoman_con1.dlg.json`) set the DLG Quest
  field to `annuminas` (entry 1) while the journal category is `Ruin of Annuminas`, so the entry was
  silently dropped. The tag now matches and the entry is written.
- **Extended (2026-07-13):** was a lore pointer with no completion; now has a head turn-in branch
  (one-time 5,000 XP, journal entry 2 with `End=1`) that hands off to the Well of Souls scribe.
- **Scripts:** the head-reaction branch is `sc_hanee_head.nss` / `at_hanee_head.nss` at the top of
  Hanee's `StartingList`; the 5,000 XP is one-time per character (local int `hanee_head_reward`).
  The area (`ruinsofannuminas`) and its content already existed.

### The Well of Souls

- **Journal tag:** `The Well of Souls`
- **Roadmap:** `gondor-scribe`
- **Fixed (2026-07-13):** the quest-giver NPC had been designed but never created or placed — the
  `gondorscribe` conversation, journal category, condition/action scripts and the boss all existed,
  but no creature carried the conversation, so the quest was unstartable. The Gondor Scribe is now
  placed and the turn-in reward was raised from 4,000 to **10,000 XP**.
- **Builder note:** the giver is `gondorscribe.utc.json` (base `comfemale002`, Tag `GondorScribe`,
  FactionID 6, Plot), placed in `area011.git` / `.gic` beside the Gondorian wizards. The scribe
  payout in `at_008.nss` is 10,000 XP.
- **Disambiguation:** the boss is **Azagoth** in the Ruins of Annuminas — *not* Moria Byss and not
  the Balrog of Moria (`azagoth001`, tag `TheBalrogofMoria`), which is a separate creature.
- **Open point:** the Annuminas Key is only granted on the scribe's paths, so on the Hanee-first
  route the four key-locked chests in the ruins are reached before the key exists (they remain
  pickable — `KeyRequired=0`).

### Gloison's Heirloom

- **Journal tag:** `Gloison's Heirloom`
- **Fixed (2026-05-28) — this was unbuilt scaffolding, not a simple bug.** The earlier diagnosis was
  wrong on several points:
  - **Gerrey is the antagonist, not the giver.** His blueprint is a hostile CR-17 mob whose
    conversation (`gloisonscoat.dlg.json`) is just a combat bark. He was never placed — now placed
    in the Ruins of Dale, carrying the heirloom as droppable loot.
  - **`sc_001.nss` never blocked anything.** `Random(100) >= 100` can never be true (0–99), so the
    conditional always returns TRUE. It needed no change.
  - **The heirloom item already existed** (`item029.uti.json`, tag `GloisonsFamilyStone`) — nothing
    to create.
  - **The real gap was a quest-giver.** The existing friendly dwarf *Gloin King Under the Mountain*
    (uses `gloingreet.dlg.json`, placed in Erebor) was extended into the giver: offer → accept
    (journal 1) and a heirloom turn-in (journal 2 + reward) via new scripts `sc_glsn_have` and
    `at_glsn_rwd`.

### Kallrist Tiger Hunt

- **Journal tag:** `Kallrist Tiger Hunt`
- **Fixed (2026-05-28):** a `Kallrist Tiger Hunt` journal category was added with an open-ended
  (non-completing) entry, and `at_sald01.nss` (Sald's accept node) now sets it via
  `AddJournalQuestEntry`. This was the quest the player reported as "AWOL" — it was always
  functional, it just had zero journal presence.
- **Scripts:** Sald inspects hearts via `sc_sald05`, destroys the heart, pays 200 gp.
- **Areas:** the island has 9 areas — `kallristinner`, `kallristeastshor`, `kallristnorthsho`,
  `kallristsouthsho`, `kallristwestshor`, `kallristouterban`, `kallristdarkrim`,
  `kallristcryptlow`, `kallristcryptupp`. Tiger blueprint `kallristtiger.utc.json` (CR 6, drops
  `kallristtigerhea`).
- **Future idea:** a "ten hearts delivered" milestone entry (e.g. 500 XP + a unique item from Sald).

### Paths of the Dead

- **Journal tag:** `paths_of_the_dead`
- **Scripts:** `q_potd_start.nss` (entry 10), `dunharrowking.nss` (entry 1), `arag_ondeath.nss`
  (entry 30), `q_potd_reward.nss` (creates `glamhring2` — Andúril — entry 40),
  `dunharrowdeath.nss` (entry 50).
- **Blueprints:** giver `aragorn_potd.dlg.json`, reward `glamhring2.uti.json`.
- **Note:** undocumented before the 2026-07-11 audit.

### Glorfindel's Curative

- **Journal tag:** `glorfindel_potion`
- **Scripts:** `at_011.nss` sets entry 1; `glorrew.nss` awards 1,700 XP and
  `bracersofglorfin.uti.json`, entry 5.
- **Blueprints:** giver `glorfindel002.utc.json`, placed in Rivendell
  (`thevalleyofriven.git.json`).
- **Note:** undocumented before the 2026-07-11 audit.

### Prestige-Order Hub (Halmir the Grey)

- **Journal tag:** none — the hub itself tracks nothing.
- **Roadmap:** `prestige-trainer-hub` (added 2026-07-15)
- **Blueprints:** Halmir (`prsg_trainer`, tag `PrestigeTrainer`; plot, immortal, commoner faction)
  is script-spawned by `prsg_spawn` from the Well of Eru OnEnter wrapper `prsg_enter` (which chains
  the area's previous `welloferuenter` — starter XP, donations chest, forge scan, leash —
  unchanged).
- **Waypoints:** `AP_prestigehub_1` must be placed in `thewelloferu` before he appears (scripts
  no-op gracefully until then). **This waypoint gates the hub and every order branch — highest
  leverage placement on the list.**
- **Framework:** the shared gating framework the twelve order quests reuse lives in `prsg_inc.nss`:
  `PRSG_MeetsLevel`, `PRSG_HasClass`, the `PRSG_LVL_*` table, the per-order conditionals `prsg_c_*`,
  and a documented `prestigedb` campaign-DB stage idiom (`PRSG_GetStage` / `PRSG_SetStage`).
  Summary line is token 6381.
- **UAT:** scripted and built, pending in-game UAT.

### The Cipher in the Inn (Harper Scout initiation)

- **Journal tag:** `pc_harper` · **Roadmap:** `harper-scout-quest` (2026-07-15)
- **State:** `prestigedb`, order key `harper`, stages 0–3; see `q_hrp_inc.nss`.
- **Scripts:** `q_hrp_start`, `q_hrp_solve`, `q_hrp_finish`; contact conversation `q_hrp_conv`.
- **Blueprints:** Della (`q_hrp_contact`, tag `HarperContact`; plot, commoner faction) is
  script-spawned by `q_hrp_spawn` from the Prancing Pony OnEnter wrapper `q_hrp_ent1` (which chains
  the previous `leash_to_area`).
- **Waypoints:** `AP_harperscout_1` in `theprancingpo001`; accepting the errand also re-runs the
  spawn check.
- **Design delta:** the design card's Rivendell/Lothlórien contacts were folded into dialogue to
  keep the quest compact.
- **UAT:** pending in-game UAT.

### The Banner of the West (Knight of Westernesse initiation)

- **Journal tag:** `pc_pdk` · **Roadmap:** `knight-westernesse-quest` (2026-07-16)
- **State:** `prestigedb`, order key `pdk`, stages 0–6; muster tally under `pdk_command` /
  `pdk_post_*` — see `q_kwn_inc.nss`.
- **Scripts:** `q_kwn_start`, `q_kwn_muster`, `q_kwn_guard`, `q_kwn_rally`, `q_kwn_banner`,
  `q_kwn_plant`, `q_kwn_finish`; captain `q_kwn_capt`.
- **Blueprints:** the Gate Captain and gate-watch guardsmen are **existing placed NPCs, reused**
  (`gondorianguar005` / `gondorianguar001`; instances carry post indexes 1–7 — seven posts for a
  three-post muster so a few dead guards can't strand the quest until reboot). Only the banner-stone
  (`q_kwn_stone`, tag `kwn_bannerstone`) is new, script-spawned by `q_kwn_spawn` from the Pelennor
  OnEnter wrapper `q_kwn_ent1` (chains the previous `d_cleartrash`).
- **Waypoints:** `AP_knightwest_1` in `thepelennorfield`; accepting the proving and taking the
  standard both re-run the spawn check.
- **Design delta:** the escort-across-the-field ("each guardsman who survives adds +1 command") was
  compacted to the muster count — no henchman AI, same fiction.
- **UAT:** pending in-game UAT.

### The Twenty-First Tomb (Pale Master initiation)

- **Journal tag:** `pc_palemaster` · **Roadmap:** `pale-master-quest` (2026-07-16)
- **State:** `prestigedb`, order key `pale`, stages 0–3; `q_pal_inc.nss`.
- **Scripts:** `q_pal_start`, `q_pal_tomb`, `q_pal_finish`.
- **No new placements, no admin waypoint:** the twenty-first tomb is an existing placed sarcophagus
  in `breecryptlowerle` ("Coffin", tag `NW_VAMPIRE_SHAD`) whose instance OnOpen now runs
  `q_pal_tomb`, chaining the instance's previous treasure script `nw_o2_classhig` unchanged.
- **Anti-farm:** turn-in is a `GetItemPossessedBy` reagent check; finish only fires from stage 2
  with the dust in hand.
- **UAT:** pending in-game UAT.

### The Unlit Deep (Shadowdancer initiation)

- **Journal tag:** `pc_shadowdancer` · **Roadmap:** `shadowdancer-quest` (2026-07-16)
- **State:** `prestigedb`, order key `shadow`, stages 0–3; `q_shd_inc.nss`.
- **Scripts:** `q_shd_start`, `q_shd_well`, `q_shd_finish`.
- **No new placements, no admin waypoint:** the objective is the existing placed well in
  `balinstomb` ("DeepWell", tag `DeepWell`) whose instance OnUsed now runs `q_shd_well`, chaining
  the previous sound-flavor script `balintmb_dpwell` unchanged.
- **Checks:** `QSHD_CarriesLight` covers all equipment slots (torch base type or Light item
  property) plus Light/Continual Flame creature effects; darkvision/ultravision sheds no light and
  does not count.
- **UAT:** pending in-game UAT.

### The Warden's Mark (Arcane Archer initiation)

- **Journal tag:** `pc_arcanearcher` · **Roadmap:** `arcane-archer-quest` (2026-07-16)
- **State:** `prestigedb`, order key `archer`, stages 0–3; `q_arc_inc.nss`.
- **Scripts:** `q_arc_start`, `q_arc_target`, `q_arc_finish`.
- **No new placements, no admin waypoint:** one of the two existing archery-target placeables in
  `rivendell`, retagged `WardenMark` and flipped usable (Static 0, Useable 1, OnUsed
  `q_arc_target`; it previously had no OnUsed, so nothing is chained).
- **Checks:** `QARC_ComesAsArcher` requires a longbow/shortbow in the weapon hand and any item in
  the arrow slot; crossbows and slings don't count.
- **UAT:** pending in-game UAT.

### The Old Wyrm's Fire (Red Dragon Disciple initiation)

- **Journal tag:** `pc_dragondisciple` · **Roadmap:** `red-dragon-disciple-quest` (2026-07-16)
- **State:** `prestigedb`, order key `rdd`, stages 0–3; `q_rdd_inc.nss`.
- **Scripts:** `q_rdd_start`, `q_rdd_forge`, `q_rdd_finish`.
- **No new placements, no admin waypoint:** the existing "The Forge of Durin" anvil placeable in
  `lonelymountainma`, retagged `DurinForge` (already usable; OnUsed `q_rdd_forge` added — it
  previously had no OnUsed, so nothing is chained; no script referenced its old `Anvil` tag).
- **Checks:** `QRDD_BloodIsWarded` covers the five standard elemental-ward spells only via
  `GetHasSpellEffect` — item-borne permanent fire resistance can't be detected by script and
  deliberately doesn't count.
- **UAT:** pending in-game UAT.

### The Quiet Knives (Assassin initiation)

- **Journal tag:** `pc_assassin` · **Roadmap:** `assassin-quest` (2026-07-16)
- **State:** `prestigedb`, order key `assn`, stages 0–3; `q_asn_inc.nss`.
- **Scripts:** `q_asn_start`, `q_asn_drop`, `q_asn_finish`.
- **No new placements, no admin waypoint:** the existing wine barrel placeable in `bree` (instance
  of `barrel001`), retagged `AsnDeadDrop` (already usable and Plot — unbashable — with no previous
  OnOpen/OnUsed, so nothing is chained; no script referenced its old shared `WineBarrel` tag).
- **Checks:** the unseen check is the stealth-mode *toggle* (`QASN_IsUnseen`,
  `GetActionMode(ACTION_MODE_STEALTH)`), not a Hide roll.
- **Reward design:** Pick Pocket / Open Lock / saves vs. poison deliberately avoid the Shadowdancer
  boots' Hide / Move Silently / Tumble.
- **UAT:** pending in-game UAT.

### The Sworn Blade (Weapon Master initiation)

- **Journal tag:** `pc_weaponmaster` · **Roadmap:** `weapon-master-quest` (2026-07-16)
- **State:** `prestigedb`, order key `wm`, stages 0–3; `q_wpm_inc.nss`.
- **Scripts:** `q_wpm_start`, `q_wpm_dummy`, `q_wpm_finish`.
- **No new placements, no admin waypoint:** the first of three existing Combat Dummy placeables in
  `minastirith` (instance of `plc_cmbtdummy`), retagged `WMTrialPost` and flipped usable + plot (it
  was Static/non-usable with no scripts; no script referenced the old shared `Combat Dummy` tag, and
  the other two dummies keep it).
- **Checks:** reads the weapon's `WeaponOfChoiceFeat` from `baseitems.2da` and checks `GetHasFeat` —
  covers every melee base item with a Weapon of Choice feat, stock and CEP alike; ranged weapons and
  non-weapons read as blank and fail.
- **UAT:** pending in-game UAT.

### The Shield of Others (Divine Champion initiation)

- **Journal tag:** `pc_divinechampion` · **Roadmap:** `divine-champion-quest` (2026-07-16)
- **State:** `prestigedb`, order key `divch`, stages 0–3; `q_dvc_inc.nss`.
- **Scripts:** `q_dvc_start`, `q_dvc_altar`, `q_dvc_finish`.
- **No new placements, no admin waypoint:** the existing Altar of the Istari placeable in
  `minastirithtemp` (instance of `plc_altrgood`), retagged `DvcVigilAltar` with `q_dvc_altar` on its
  OnUsed (already usable + plot with no scripts; no script referenced the old tag
  `AltarShrineGood`).
- **Checks:** `GetItemInSlot(INVENTORY_SLOT_LEFTHAND)` against `BASE_ITEM_SMALLSHIELD` /
  `LARGESHIELD` / `TOWERSHIELD` = 14/56/57, verified in `ovr/nwscript.nss`.
- **Reward design:** Heal / Persuade / saves vs. divine (`IP_CONST_SAVEVS_DIVINE` = 6; no vs-evil
  save constant exists).
- **UAT:** pending in-game UAT.

### The Unbroken Stone (Dwarven Defender initiation)

- **Journal tag:** `pc_dwarvendefender` · **Roadmap:** `dwarven-defender-quest` (2026-07-16)
- **State:** `prestigedb`, order key `dwdef`, stages 0–3; `q_dwd_inc.nss`.
- **Scripts:** `q_dwd_start`, `q_dwd_stone`, `q_dwd_finish`; conditional `q_dwd_c_off`.
- **No new placements, no admin waypoint:** the existing Balin headstone placeable in `balinstomb`
  (instance 86 of `plc_headstone`), retagged `DwdBalinStone` with `q_dwd_stone` on its OnUsed
  (already usable + plot with no scripts; no script referenced the generic old tag `Headstone`, and
  the Shadowdancers' DeepWell hook in the same area — instance 52 — is untouched).
- **Checks:** reads the chest armor's base AC from `parts_chest.2da` (the module's `zep_cr_canca`
  idiom) and requires 6+, so enhancement bonuses on light armor can't fake it. Race gate checked
  defensively in `q_dwd_c_off` alongside the class (`CLASS_TYPE_DWARVEN_DEFENDER` = 36,
  `RACIAL_TYPE_DWARF` = 0, both verified in `ovr/nwscript.nss`).
- **Reward design:** Craft Armor / Taunt / saves vs. sonic (`IP_CONST_SAVEVS_SONIC` = 15, for the
  drums in the deep; no vs-traps save constant exists).
- **UAT:** pending in-game UAT.

### The Second Skin (Shifter initiation)

- **Journal tag:** `pc_shifter` · **Roadmap:** `shifter-quest` (2026-07-16)
- **State:** `prestigedb`, order key `shift`, stages 0–3; `q_shf_inc.nss`.
- **Scripts:** `q_shf_start`, `q_shf_pool`, `q_shf_finish`.
- **No new placements, no admin waypoint:** the existing pool placeable at Beorn's homestead
  (instance 36 of `zep_pool003` in `beorn`), retagged `ShfBeornPool` and made usable/dynamic/plot
  with `q_shf_pool` on its OnUsed (it had no scripts; no script referenced the generic old tag
  `ZEP_POOL003`).
- **Checks:** loops active effects for `EFFECT_TYPE_POLYMORPH` (the module's proven detection idiom
  from the DM wand's un-polymorph routine). Class gate `CLASS_TYPE_SHIFTER` = 35.
- **Reward design:** an amulet on purpose — neck-slot properties ride through most polymorph shapes.
  Animal Empathy / Search / saves vs. mind-affecting (`IP_CONST_SAVEVS_MINDAFFECTING` = 11).
- **UAT:** pending in-game UAT.

### The Fall (Blackguard initiation)

- **Journal tag:** `pc_blackguard` · **Roadmap:** `blackguard-quest` (2026-07-17)
- **State:** `prestigedb`, order key `blackg`, stages 0–3; `q_bkg_inc.nss`.
- **Scripts:** `q_bkg_start`, `q_bkg_altar`, `q_bkg_finish`.
- **No new placements, no admin waypoint:** the existing unique torture-rack placeable in the Keep
  of Barad-Dûr (instance 94 of `plc_torture1` in `baraddurkeep`), retagged `BkgFallAltar` and made
  usable/dynamic with `q_bkg_altar` on its OnUsed (it was static with no scripts; no script
  referenced the generic old tag `Torture Equipment`).
- **Checks / alignment:** class gate `CLASS_TYPE_BLACKGUARD` = 31. The permanent shift is
  `AdjustAlignment(oPC, ALIGNMENT_EVIL, 50, FALSE)` — the `FALSE` keeps it to the swearer, not the
  party — applied **only** on the stage 1→2 transition so it can never be farmed.
- **Reward design:** Bluff / Use Magic Device / saves vs. Negative (`IP_CONST_SAVEVS_NEGATIVE` =
  12).
- **UAT:** pending in-game UAT.

### The Path of Meaning (MeaningWave)

- **Journal tag:** `MW Path of Meaning`; entries set by `mw_unlock_inc.nss`.
- **Scaffolding:** seven additional loyalty quest categories exist in the journal (`MW Jordan
  Peterson Loyalty` etc.) with placeholder text "Content forthcoming." No scripts reference these
  yet. They are scaffolded for future content — loyalty quests for each guide after you unlock them.

### Server Info Journals

- **Delivery:** `hgll_cliententer.nss` delivers **eight** categories on every login, idempotently,
  all with `End=1` so they land in the player's Completed section: `rules`, `website`,
  `modcustoms`, `mod_progress`, `mod_death`, `mod_forge`, `mod_systems`, `mod_factions`.
- **Guilds retired on purpose (2026-07-15)** (roadmap idea `guilds-journal-never-delivered`):
  delivery of the `guilds` category was briefly added on 2026-07-14, then removed at the admin's
  direction — the guild system is retired/suspended, so the journal is deliberately withheld. The
  category remains in `module.jrl.json` and can be re-enabled with one line in
  `hgll_cliententer.nss` if guilds return.
- **Minor open point:** the `website` category's display `Name` is still literally "Website" while
  its content is now the Discord invite (`https://discord.gg/VpAtSpe`) in `module.jrl.json`.
- **History:** `mod_enter.nss` was dead code, never wired to any event — which is why players never
  received these entries at all before the fix.

### Unjournaled quests

Several quest scripts called `AddJournalQuestEntry` with tags that had no matching journal category.
NWN silently ignores them, so the quest logic ran but players saw no journal entries.

| Quest / script | Tag | Status |
|---|---|---|
| Green Dragon quest (`gdqc2.nss`, `gdrev1/2/3.nss`) | `gdquest1` | Journal added — category "The Green Dragon Inn" (entry 1 accept, entry 2 complete). Reward 500 XP + 1,000 gp via `gdrev1`. |
| Gwathdor quest (`gqstart.nss`) | `gwathquest` | Journal added — category "The Oasis of Gwathdor" (entry 1). **Only a start state is scripted; no completion entry is set anywhere yet.** |
| Cursed Grave undead (`b_undead_dest.nss`) | `cursedgrave` | Journal added — category "The Cursed Grave" with entry 2 (`End=1`) and category XP=250, so `GetJournalQuestExperience` returns 250. |
| Ported campaign quests (m2/m3 plot scripts) | `m2q2_Jax`, `M3Q04_*`, etc. | Campaign module content ported in; original journal categories not ported. **Intentionally left alone** — can be removed or wrapped into purpose-built persistent-world equivalents in a future pass. |

---

## Unfinished / partly journalled threads

Moved here from the public `docs.manual/QuestGuide.html` on 2026-07-18, when the guide dropped its
status badges. The player-facing page now shows only developed/deployed content plus a single note
pointing at the Roadmap's **Needs Manual Finishing** section — these two caveats live here instead:

- **In the world, without journal tracking yet.** A handful of older quest threads (the Green Dragon
  Inn, the Oasis of Gwathdor, the Cursed Grave, and some remnants ported in from the original
  campaign modules) are playable in places but only partly journalled. A player who stumbles into one
  will see nothing in their log. See the ported-quest table above for the per-thread status.
- **MeaningWave loyalty quests.** Each of the seven guides has a loyalty quest scaffolded for a
  future update — follow-up tasks available after the guide is unlocked. The journal categories exist
  already; the content is still unwritten. Suggested reward when built: 1,000–1,500 XP per task (see
  the balance table below).

---

## Balance & reward notes

Current XP and gold rewards mapped against expected player level — with recommendations.

| Quest | Level range | Current reward | Assessment | Suggested reward |
|---|---|---|---|---|
| Bill Ferny's Ring | 1–10 | 500 XP + 200 gp *(was 150)* | Raised to 500 XP. A small unique (e.g. a *Ferny's Grudge* dagger) remains an optional future addition. | 500 XP + 200 gp ✓ applied |
| The Miller's Son | 1–10 | 450 XP *(was 150)* | Raised to 450 XP. An optional *Bree Miller's Favour* token remains a future idea. | 450 XP ✓ applied |
| Feeding Tharbad | 5–15 | 500 XP + Book of the Cora *(was 200)* | Raised to 500 XP. The Book already carries useful properties, so no item change was needed. | 500 XP ✓ applied |
| Elrond's Request | 15–30 | 2,000 XP + Elrond's Writ | Reasonable for a two-part chain that requires entering Moria. **Verify Elrond's Writ has a tangible use.** | Keep 2,000 XP. Ensure *Elrond's Writ* unlocks something meaningful — e.g. access to Rivendell's inner vault store, or a permanent +1 to saves via `SetLocalInt`. |
| The Well of Souls | 30–45 | **10,000 XP** + Annuminas Key *(was 1,000, then 4,000)* | Resolved. The old 1,000 XP was trivial for a deep boss; raised to 4,000 on 2026-05-28 and to 10,000 on 2026-07-13, addressing the "chicken feed" complaint. | 10,000 XP ✓ applied. A named soul-themed item drop remains a future idea. |
| Kallrist Tiger Hunt | 10–20 | 200 gp/heart, repeatable | Fair rate for CR 6 enemies. Journal-presence problem resolved (open-ended category added). | Journal category ✓ added. A one-time 10-hearts-delivered milestone (500 XP + a unique item from Sald) remains optional. |
| MeaningWave (per guide) | any | 500 XP per guide, 2,000 XP finale | Good. The spread across the game's levels means it never feels too easy or too hard. Finale reward (the mixtape item) is thematic. | Keep as-is. When loyalty quests are implemented, 1,000–1,500 XP per loyalty task would be appropriate. |

**General balancing principle:** NWN1 EE characters gain roughly 1,000–3,000 XP per level in the
early tiers from combat alone. A quest reward should represent a meaningful bump — roughly half a
level's worth of combat XP at the quest's target tier. Early quests (levels 1–10) should give
400–800 XP; mid quests (15–30) should give 1,500–3,000 XP; end-game quests 3,000–8,000 XP.

**Item rewards:** most quests give XP and gold only. Adding a unique named item to each quest — even
a minor one — significantly increases perceived value and gives players something to talk about.
Items don't need to be powerful; they need to be memorable.

> This table covers only 7 of the ~40 documented quests and predates the 2026-07 quest wave. It
> needs a refresh pass against the current Active Quests list.

---

## Investigating player reports

Three historical bug reports, traced to their roots.

### "The Kallrist Island tiger quest is AWOL"

**Verdict: quest existed but had no journal tracking — now resolved.** The Kallrist Tiger Hunt was
always fully functional — NPC Sald, the tiger creatures, the *Kallrist Tiger Heart* item, and the
200 gp payout all work. Players never saw it in their quest log because there was no journal
category. **Fixed:** a `Kallrist Tiger Hunt` category was added and wired into Sald's accept node
(`at_sald01.nss`).

### "The demon north of Bree quest is broken — gave 1,000 XP, chicken feed by the time you can kill it"

**Verdict: no demon exists near Bree today. The 1,000 XP report points to the Well of Souls.** A
thorough search of all creature placements in and around Bree and the surrounding north areas finds
no demon creature. The 1,000 XP reward described matches `at_008.nss` — the Gondor Scribe's payout
for bringing Azagoth's Head. Azagoth spawns in the Ruins of Annuminas north of Bree (via an
encounter), not in Moria. Either a demon NPC was placed near Bree by a DM in the past and later
removed from the GIT, or the player was describing the Azagoth / Well of Souls payout. Either way
the complaint was valid — the `at_008.nss` payout was raised to 4,000 XP on 2026-05-28 and to
**10,000 XP** on 2026-07-13, when the missing Gondor Scribe was also finally placed (the quest had
been unstartable until then).

### "Elrond's quest is fixed, but existing journals (server updates) got removed when accepting it"

**Verdict: Elrond's scripts never clear any journal entries. The server-info journals were simply
never given.** No script in the module calls `RemoveJournalQuestEntry` or any equivalent. The Elrond
quest sets entries via the DLG engine's built-in Quest field, which only *adds* entries.

The real problem: `mod_enter.nss` (which contained the server rules/guilds/website journal delivery)
was dead code, not wired to any event, so players never received those entries. Before and after
speaking to Elrond the server-info journals were absent — because they were never given. The timing
coincidence made it look like Elrond's quest was clearing them.

**Fixed (corrected 2026-07-11):** `AddJournalQuestEntry` calls for `rules`, `website` and the six
`mod_*` journals were added directly to `hgll_cliententer.nss`, the real OnClientEnter handler, and
run idempotently on every login. The `guilds` journal is deliberately excluded as of 2026-07-15. The
forum URL in the `website` entry has since been refreshed to the community Discord.

---

## Historical corrections to this guide

- **2026-05-28** — the fixes described throughout were implemented in module source. Three earlier
  diagnoses were corrected during implementation: `sc_001.nss` never blocked Gloison's conversation
  (its `Random(100) >= 100` branch can never fire, so it always returns TRUE); `hgll_cliententer.nss`
  had no pre-existing first-login check to hang the server-info journals from; and the *Book of the
  Cora* already carries useful properties.
- **2026-07-11 audit pass** — a re-audit against the live module found the guide had drifted. Two
  fully-scripted reward quests were undocumented and were added (Paths of the Dead, Glorfindel's
  Curative); the Guilds server-info journal was confirmed as deliberately not delivered; and The
  Well of Souls was found unstartable with no Gondor Scribe placed (fixed 2026-07-13). The six
  `mod_*` server-info journals that *are* delivered were documented.
- **2026-07-18 public/internal split** — `QuestGuide.html` was rewritten as a player-facing document
  (summary table, Working / In Development badges only) and every DM note, script resref, waypoint
  tag, DB name, roadmap id and triage narrative was moved into this file.
