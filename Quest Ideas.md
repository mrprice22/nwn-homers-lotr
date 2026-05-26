# Quest Ideas — Developer Implementation Notes

Player-facing content (quest descriptions, rewards, class questlines, prestige quests) lives at
`docs/manual/Quest Ideas.html`. This file is the implementation reference: per-quest scripting notes,
authoring conventions, and the module compatibility audit.

---

## Authoring conventions

- Journal entries: add to `module.jrl.json` (`Categories.value`) with a unique `Tag`, unique stage
  `ID`s, and `End=1` on the final stage. Trigger via `AddJournalQuestEntry("MyTag", <stageID>, oPC)`.
- Quest progress: `GetLocalInt(oPC, "<questvar>")` for in-session state;
  `GetCampaignInt("homerlotr", "<key>", oPC)` / `SetCampaignInt(...)` for persistence.
  The module uses **no NWNX, no SQL** — campaign DB only.
- Dialogue conditionals: `int StartingConditional()` (see `sc_044.nss`); dialogue actions:
  `void main()` (see `at_014.nss`). Match naming pattern `sc_NNN` / `at_NNN` or use descriptive names.
- Daily/weekly cooldowns: store `GetCalendarYear() * 12 * 28 + GetCalendarMonth() * 28 + GetCalendarDay()`
  as a per-PC campaign int (key `lastdone_<questtag>`); compare at quest start.
- Server-state vars: `SetCampaignInt(GetModule(), "<key>", n)` — module-scoped, persists across sessions.
  Reset via heartbeat comparisons in `bleeding.nss`. Decay pattern: `GetCalendarDay() % 7 == stored_day`.
- Prestige-class gating: `GetLevelByClass(CLASS_TYPE_<X>, oPC) >= 1` in the giver's starting conditional.
  All prestige givers should live on a single hub NPC near `thewelloferu`.

---

## Faction Quests

> **Note on factions.** `repute.fac.json` ships only the engine-required factions (PC/Hostile/Commoner/
> Merchant/Defender) plus three globals: **Good**, **Evil**, **Neutral**. There is no Gondor / Rohan /
> Rivendell / Lothlórien / Mordor / Isengard / Goblin-town / Haradrim faction yet. "Rep token" rewards
> collapse to Good/Evil standing unless `repute.fac.json` is expanded first (10–15 new factions, alignment
> blocks of pairwise `RepList` entries). Until then, implement "Good rep" / "Evil rep" as
> `AdjustReputation(oPC, GetObjectByTag("FactionAnchor_<name>"), +/-N)` against a single anchor NPC.

### Good Factions

**[Daily] The Palantír Watch** *(Lvl 20+)*
> Use `toweroforthanc.are.json` (Orthanc palantír) or `minastirith.are.json` (Anor stone). Lore-keeper
> UTC with low HP follows via `ActionForceFollowObject(oPC, 2.0f)` — clone from any existing escort creature.
> Spawn 2–3 wave of Hostile Uruks via `CreateObject` on a heartbeat trigger inside the area. Stacking token:
> UTI with `Stacking=TRUE`, `Cost=0`; persistence via inventory count.

**[Weekly] Riders of the Mark** *(Lvl 30+)*
> Areas exist: `helmsdeep001`, `pathtohelmsdeep`, `dunland`, `dunlandwarparty`. Rohirrim NPCs:
> `riddermarkswords.utc.json`, `riddermarkguardi.utc.json`. Wave defence: spawn 4 waves of escalating
> Hostile Uruks on a `DelayCommand` chain; "reinforcements" = spawn friendly `riddermark*` + `VFX_FNF_HORN_OF_VALHALLA`.
> **Note:** +8 AC armor exceeds NWN's item ceiling; encode as AC +5 plus situational bonuses (e.g. AC vs
> Goblinoid +3).

**[Weekly] The White Council's Errand** *(Lvl 40+)*
> Eregion/Ost-in-Edhil not in module — substitute `ruinsofannuminas.are.json` or `tharbadbridge`/`tharbadwest001`.
> Gandalf: `gandalf001.utc.json`. Saruman: `sarumanthewhi001.utc.json`, conv `saurman`. Persist betrayal:
> `SetCampaignInt("homerlotr", "whitecouncil_status", -1, oPC)` so Gandalf's dialogues thereafter refuse
> the PC via `StartingConditional`.

**[One-Off] The Dead Marshes Lantern** *(Lvl 35)*
> `deadmarshes.are.json` and `deadmarshcrypts.are.json` exist. "Will save every 30s": area `OnHeartbeat`
> fires every 6s; check `GetCalendarSecond() % 30 == 0` or use a per-PC counter local. On failed save:
> `EFFECT_TYPE_CONFUSED` for 6s. Elven Waystone: UTI script `JumpToLocation(GetLocation(GetWaypointByTag("WP_Rivendell_Hub")))`,
> charges decremented on use.

**[One-Off] Eagles of the Eyrie** *(Lvl 50+)*
> No Eyrie area — nearest: `mistymountainsa.are.json` / `mistymountainsb.are.json`. Gwaihir: new UTC,
> Giant Eagle appearance (CEP `c_eaglegt` or appearance 116/137). Eagle Courier: placeables in each
> Free-Peoples capital with destination options; gate on `GetCampaignInt("homerlotr","eagle_courier_unlocked",oPC) == 1`.

### Evil Factions

**[Daily] Sowing Discord in Bree** *(Lvl 15+)*
> Bree areas: `bree.are.json`, `theprancingpo001`, `theprancingpo002`, `ponyinn3`, `billfernyshouse`.
> "Plant letter": `CreateItemOnObject` into a placeable inventory or `SetUseableFlag`; sheriff arrival via
> heartbeat-counted spawn after N rounds. Morgul silver: stacking UTI parallel to gold.

**[Weekly] The Sacking of Pelargir** *(Lvl 35+)*
> Pelargir not in module — substitute `hiddenport.are.json` or `gondorwesta`/`gondorwestb`. PvP workaround:
> `SetIsTemporaryEnemy()` between opposing-faction PCs on entry. +10 keen weapon: encode as Enhancement +5
> plus typed damage bonuses to stay below the +20 BAB AC race.

**[Weekly] Unmaking the Wards** *(Lvl 40+)*
> Areas: `lothlorien`, `lothloriennorth`, `lorienforrestout`, `lorienhightreele`, `lothlorienflets`.
> Ward-stones: UTP placeables, `OnUsed` decrements area-local counter; on count==3, journal advance + buff.
> Detection traps: `TRAP_BASE_TYPE_*` from NWN palette. Haldir: no UTC — clone Elvish guard, tag `Haldir`.

**[One-Off] The Nine Are Abroad** *(Lvl 45)*
> Witch King: `witchking.utc.json`. Nazgûl guildhouse: `nazgulguildhouse.are.json`. "Sunrise" timer:
> `GetTimeHour()` rolling past `Mod_DawnHour` (currently 6). Fallback variant: shoes held by a 3-NPC
> Hostile Maia patrol in a randomized area, picked on quest start.

**[One-Off] Saruman's Voice** *(Lvl 25)*
> `minastirithtemp.are.json` or `minastirith.are.json` for the Steward's hall. Bluff/Persuade gating in
> dialogue conditional: `GetSkillRank(SKILL_BLUFF, oPC) + d20 >= DC`. Failure branch:
> `SetIsTemporaryEnemy()` + `ActionAttack(oPC)` on four nearest guards. Ring of Silver Tongue: UTI
> base 52 (ring), `Skill Bonus: Bluff +5`, `Skill Bonus: Persuade +5`.

---

## Class Questlines

### Capstone item constraints
- "+14/+15 equivalent" = Enhancement +5 + typed damage bonuses (e.g. 2d6 vs Evil, 1d6 fire). NWN caps
  weapon enhancement at +20 but convention is +5 max for the enhancement property; stack typed bonuses.
- Dual "+14/+14" weapons: same encoding — Enhancement +5 + sneak-attack-proxy bonus dice.
- Class restriction: UTI property `Use Limitation: Class` matching the `class.2da` row.
- Spell-DC modifiers ("Sceptre of Annúminas +3 DC all schools"): **not a stock item property**. Substitute
  `Spell Penetration +5` (stock) or per-school custom hak additions. "+2 caster level" similarly has no
  stock property — rewrite as 3×/day Maximize-tagged spell use.

### Fighter — The Unbroken Shield
> Areas: `theprancingpo001`, `bree`, `thepelennorfield`, `gondoremynarnen`, `rivendell`,
> `thesmithyofriven`, `osgilbridge`, `blackgatge`, `dunharrow`, `forgottenking`.
> Aragorn: `aragornsonofarat.utc.json`.
> Broken sword: create `narsil_broken` / `narsil_reforged` UTIs; dying captain `OnDeath` gives broken sword;
> smiths' dialogue checks `GetItemPossessedBy(oPC, "ore_mithril")` etc., consumes them, swaps items.
> Osgiliath wave defence: 100 heartbeats (10 min); spawn 4 waves on `DelayCommand` chain.
> Aeglos Reborn: Spear (BaseItem=2), Enhancement +5, Damage Bonus 2d6 vs Evil, Ability Bonus STR +5,
> On-Hit Slow (nearest CostTable row ≈ DC 22), Light: 20m white.

### Wizard — The Colour of Power
> Areas: `shirehobbiton001`, `bagend001`, `fangornforest`, `fangornoutskirts`, `toweroforthanc`,
> `towerofothancsar`, `isengardinnerrim`, `isengardmagicroo`, `mirkwoodcentral*`, `dolguldur*`,
> `cavesofdolguldur`, `blackgatge`. NPCs: Treebeard (`TreeBeard`), Gandalf (`gandalf001`),
> Saruman (`sarumanthewhi001`), Radagast (`radagastthebrown`).
> "Read three tomes": UTP placeables, `OnUsed` sets `SetLocalInt(oPC, "wiz_tome_<n>", 1)`.
> Colour choice: `SetCampaignInt("homerlotr", "wizard_colour", n, oPC)` (1=White, 2=Many-Colours, 3=Brown);
> gate capstone properties on this value.
> "+2 caster level": no stock property — rewrite as 3×/day Maximize Fireball via OnActivate/OnHit script.

### Rogue — The Long Shadow
> Areas: `theprancingpo001`, `breecave`, `breecaverns`, `shelobslair`, `cirithungol`,
> `thecirithungolpa`, `toweroforthanc`, `baraddur`, `baraddurkeep`, `baraddurbarracks`.
> Gollum: `gollum.utc.json`. Shelob: `shelob001.utc.json`.
> "No combat" enforcement: `SignalEvent(area, EventUserDefined(99))` on combat-init aborts quest;
> simpler: Stealth check on each guard's perception `OnPerception`.
> "Sneak Attack +3d6": use `Massive Critical: 3d6` or `Damage Bonus: Piercing 3d6` — no stock SA property.
> Dual swords: two UTIs, Enhancement +5 + typed bonuses each; Use Limitation: Rogue.

### Druid — The Breathing of the World
> Areas: `oldforest001`, `fangornforest`, `fangornoutskirts`, `rhosgobel`, `rhosgobeltower`,
> `dolguldur`, `pathtohelmsdeep`, `helmsdeep001`, `minastirith`, `sharkeysmill`, `sharkeyschamber`,
> `mountdoom`, `mountdoom002`.
> Tom Bombadil: no UTC — author (high-level commoner, `OnSpawn` applies `EffectImmunity` all damage types).
> Old Man Willow: clone Treant appearance (CEP creature row).
> "Animal companion +8 all stats": OnSpawn override calls `ApplyEffect` `EffectAbilityIncrease` per stat.
> "Terrain passive regen": OnEquip reads area tag prefix; applies `EffectRegenerate` matching biome.

### Ranger — The Uncrowned Path
> Areas: `bree`, `weatherhills`, `mirkwoodwest`, `mirkwoodcentral`, `mirkwoodeast`, `rangerwaystation`,
> `hennethannun`, `hennethannun002`, `dunharrow`, `forgottenking`, `harad`, `roadtoharad`,
> `thepelennorfield`. Aragorn: `aragornsonofarat` for handout.
> Rhûn: not in module — substitute `cardolan.are.json` or `thenorthdowns001.are.json`.
> Faramir: no UTC — clone Aragorn; tag `Faramir`.
> "+2d6 vs Evil": `Damage Bonus vs. Alignment Group: Evil 2d6` — stock. On-Crit Fear: `On Hit: Fear (DC X)` stock.

### Cleric — Flame of Anor
> Areas: `thebarrowdowns`, `minastirith`, `thehouseofhealin`, `balinstomb`, `chamberofrecords`,
> `rivendell`, `templeofilluvata`, `thealtar`, `thehallsoftruth`, `blackgatge`.
> "Cleanse 5 NPCs of Black Shadow disease": apply disease effect on 5 spawned commoners; player's Cure Disease
> removes it; each removal increments `GetLocalInt(oPC, "ne_purified")`.
> Nan Dungortheb: not in module — author or skip.
> "Aura +2 saves all" (Narya): stock only covers specific subtypes. Generic +2 needs OnEquip persistent AoE script.

### Paladin — Oath-Sworn to the West
> Areas: `minastirith`, `minastirithgates`, `edoras`, `theodenshall`, `dunharrow`, `helmsdeep001`,
> `thepelennorfield`, `osgilbridge`. Eowyn: `eowyntheshieldma.utc.json`. Theoden: `theoden002.utc.json`.
> Witch King: `witchking.utc.json`.
> No mounts in stock NWN — "mounted charge" is flavour-only unless `Mod_HorseEnabled` is set in `module.ifo.json`.
> "Smite Evil +5d6": no item property modifies smite. Implement as on-hit: target is Evil → `ApplyEffect 5d6 divine`.
> "On-kill +1 temp HP to 30": OnHitCastSpell with custom spellscript that stacks `EffectTemporaryHitpoints(1)`,
> capped at 30 via local count.

### Bard — Tales That Live Forever
> Areas: `shirebilbohouse`, `bagend001`, `lothlorien`, `morialevel1cente`, `dunland`, `dunlandwarparty`,
> `mountdoom`. Bilbo: `bilbobaggins.utc.json`. Galadriel: `galadriel.utc.json`.
> Eregion: not in module — substitute `ruinsofannuminas`.
> "Timed dialogue": sequential prompts with `DelayCommand` removing the correct option after N seconds.
> "Bardic Music doubled": modify `nw_s2_bardsong.nss` radius and duration — it is in the module's `.nss` tree
> but the change is global to all bards. Alternative: UTI property `Bonus Feat: Lasting Inspiration` (CEP feat).

### Monk — The Empty Hand of the West
> Areas: `mistymountainsa`, `mistymountainsb`, `weatherhills`, `thetrollshalls`, `lothlorien`,
> `lothlorienflets`, `shelobslair`, `thebalrogofmoria`, `theabyssofmoria`, `mountdoom`,
> `minastirith`, `theodenshall`. Balrog: `thebalrog.utc.json`.
> "Gear suppressed": OnAreaEnter `CopyItem` equipment to stash chest; chest at exit returns gear.
> "Unarmed +15": UTI BaseItem=Gloves, Enhancement +5 + typed damage bonuses. Use Limitation: Monk.
> "Stunning Fist DC +6": no stock property. Substitute `Ability Bonus: Wis +5` (Stunning Fist DCs off Wis).

### Sorcerer — Blood of the Elder Days
> Areas: `minastirith`, `cardolan`, `thenorthdowns001`, `ruinsofannuminas`, `theruinsofdale`,
> `thelonelymountai`, `lonelymountainma`, `nazgulguildhouse`, `blackgatge`.
> Smaug: no blueprint — check CEP for Red Wyrm appearance; "spirit" form uses fire elemental VFX.
> "Cast without limit 5 min": Sceptre on-use calls `RestoreSpellSlots` repeatedly on a 6s heartbeat for 50 ticks.
> "Spell DC +3 all schools": **not stock** — replace with `Spell Penetration +5` or drop.
> "Metamagic 1 slot cheaper": no engine support — replace with `Bonus Spell Slot of Level 9`.

---

## Location-Specific Quest Notes

### The Misty Mountains

**Goblin-Town Throne** *(Lvl 18)*
> Areas: `goblintownmainha`, `goblintownwarren`, `goblingategreate`, `goblingatelesser`,
> `goblingatemines`. Server-wide buff: `SetCampaignInt("homerlotr","goblin_civil_war_until", <ts + 7*86400>)`;
> area `OnEnter` checks value and halves Hostile spawn count when active.

**Pass the Pass** *(Daily, Lvl 10+)*
> Areas: `mistymountainsa`, `mistymountainsb`, `foothillsofthemi`. Difficulty selection in opening dialogue;
> gold reward = `nDiff * 200`. Stone-Giant: clone Hill Giant UTC with appearance row 158 (Stone Giant, if CEP exposes it).

**Mithril Seam** *(Weekly, Lvl 28+)*
> Areas: `theabyssofmoria`, `thebalrogofmoria`. Single-UTP "first-takes-it": `OnUsed` creates item on user
> and sets `SetCampaignInt(... "mithril_claimed_week_<weekNo>", 1)`, then destroys placeable. Weekly reset
> via heartbeat comparing `GetCalendarMonth/Day` to stored stamp.

### Fangorn Forest

**The Thirteenth Ent** *(One-Off, Lvl 32)*
> `fangornforest.are.json` / `fangornoutskirts.are.json`. Restore method branches on
> `GetLevelByClass(CLASS_TYPE_DRUID)` / `BARD` / Lore skill in dialogue conditional.
> Permanent stat item: UTI with custom spellscript that calls
> `ApplyEffectToObject(..., EffectAbilityIncrease(...), DURATION_TYPE_PERMANENT)` then `DestroyObject(oItem)`.

**Lumber Runners / Ent-Watch** *(Daily, Lvl 15+)*
> `isengardouterrim.are.json`. Server-state var: `SetCampaignInt(GetModule(), "isengard_warmachine", n)`.
> Read at `helmsdeep001.are.json` `OnEnter` to scale the wave count (Hard vs Normal).
> Both quests share the same var — Evil increments, Good decrements (clamp ≥ 0).

### Mirkwood

**The Halls of Thranduil — Jailbreak** *(Weekly, Lvl 22+)*
> `thranduilshall.are.json`. Two parallel journal tags (`thranduil_good`, `thranduil_evil`) gated by
> alignment. "Prisoner" UTC swaps based on active quest; spawn `prison.are.json` content variant on entry.

**Smaug's Lingering Curse** *(One-Off, Lvl 40)*
> `laketownthetipss.are.json` and `mirkwoodcentrals.are.json`. Crafting: smith NPC dialogue consumes
> ingredients via `DestroyObject` and returns prepared armor UTI.

**Spider Silk Harvest** *(Daily, Lvl 12+)*
> `mirkwoodwest` / `mirkwoodcentrale`. OnDeath: `CreateItemOnObject("silkbolt", oPC)`. Dynamic price:
> `gp = base_gp - GetCampaignInt(... "silk_supply") * 2` (clamped to floor). Increment supply on each NPC
> sale; decrement weekly.

### Moria

**The Twenty-First Hall** *(One-Off, Lvl 36)*
> `chamberofrecords.are.json` (Mazarbul) and `balinstomb.are.json`. Tie to existing `Elrond's Request`
> journal thread or split off via `SetLocalInt`.

**Durin's Bane Remnant** *(Weekly, Lvl 50+)*
> `thebalrogofmoria` / `theabyssofmoria`. Balrog UTC: `thebalrog.utc.json` reusable as boss. Fire-wraith
> spawns gated on `GetCampaignInt(GetModule(), "balrog_remnant_unbeat", 0)` — set to 1 by weekly heartbeat
> if not cleared.

**Claim the Deeps** *(Daily, Lvl 20+)*
> `dwarrowdelfea001` / `dwarrowdelfeast`. Control state:
> `SetCampaignInt(GetModule(), "deeps_control", n)` (1=good, 2=evil, 0=neutral); reset daily.
> Crafting table UTP `OnUsed` checks alignment vs control state.

### The Grey Havens

**Last Ship's Cargo / Harbour Watch** *(One-Off / Daily)*
> **Grey Havens not in module** — author a new coastal area or rebrand `hiddenport.are.json`. Círdan needs a
> new UTC. NWN has no swim mechanic — substitute "Movement Speed +10%" + `Immunity: Drowning` (flavour only).
> Harbour Watch difficulty reads `GetCampaignInt(GetModule(), "corsair_pressure", 0)`.

### Mount Doom / Mordor

**Cracks of Doom** *(One-Off, Lvl 58–60)*
> `mountdoom`, `mountdoom002`, `cirithungol`, `thecirithungolpa`, `shelobslair`.
> Final-room mode: `GetCampaignInt(GetModule(), "endgame_mode", 0)`. No instancing — treat as group quest,
> NWN server cap governs party size.

**Mordor Forage** *(Weekly, Evil only)*
> `mountdoom002`. Lava damage: trigger `OnEnter` applying `EffectDamage(d6, FIRE)`. Rare component: stacking
> UTI key in `Mod_OnAcquirItem`-style craft conversation.

---

## Wildcard Quest Notes

**Sméagol's Side** — pure dialogue on "Sméagol's mind" placeable. Meter:
`SetLocalInt(oPC, "smeagol_meter", n)`. Persist to `SetCampaignInt(GetModule(), "smeagol_alignment", n)`;
read by Cracks of Doom final-room script.

**The Watcher in the Water** — `thegatesofmoria.are.json`. Sequential `OnUsed` on fishing-spot UTP: 1st use
= lake trout, 2nd = octopus tentacle, 3rd = kraken-style boss (clone CEP giant aquatic creature).

**Hobbit Post** — daily rotation: `GetCalendarDay() % 5` selects recipient. `GetTimeSecond`-based bonus gold
for fast delivery. Random loot: a `treasure_post` UTI chest opened on completion.

**The Riddle Game** — `breecave.are.json` or `darkcavern.are.json`. Gollum UTC reusable. Track correct
answers via `SetLocalInt`; ≥ 5/7 = win. Random reward via `treasure_riddle` chest.

**Concerning Hobbits** — `shirehobbiton001`, `shirebilbohouse`, `bagend001`. No instancing: single "Bag End"
interior, `OnEnter` checks `GetCampaignInt(GetModule(),"bagend_owner_id")` and kicks others. Seasonal
answer: `GetCalendarMonth() / 3` indexes the branch.

**Bombadil's Errand** — `oldforest001`. Bombadil: author new UTC. "Forest rearranges":
`SetTransitionTarget`-rewrite on area heartbeat pointing transitions to varying destinations.
Abilities suppressed: `EffectCutsceneDominated` or strip equipment (same pattern as Monk capstone).

**Ents Don't Hasty** — `fangornforest`. Per-day gate: `GetCampaignInt(... "ent_story_day", oPC)` increments
only if `GetCalendarDay() != GetCampaignInt(... "ent_last_day")`. Final reward = 7-day self-destructing buff item.

**The Istari's Bet** — `emynmuil`, `nindalf`, `dagorlad`. Item suppression: same OnAreaEnter stash trick.
`GetTimeHour()`-based 24-hour check. Reward arrives via the Hobbit Post quest's daily rotation.

**Ungoliant's Hunger** — Nan Dungortheb absent; rebrand `eredduathroada.are.json`. Mirror puzzle: four UTP
placeables with rotation steps; correct sequence opens invisible trigger despawning the "unlight" (high-CR
shadow-elemental clone, 95% concealment). Phial: UTI `Cast Spell: Daylight 3 charges/day` — stock.

**The Long Winter** — Bay of Forochel absent; `icequeennest.are.json` / `icequeenlair.are.json` thematically
close. XP scale +10%: `Mod_XPScale` is static at module load — gate via wrapper `GiveXPToCreature` script
multiplying by seasonal modifier. State: `SetCampaignInt(GetModule(), "long_winter_phase", n)`.

---

## New Quests — Implementation Details

These quests were authored against `unpacked/`. All required areas already exist.

**Ferny's Return** *(One-Off, Lvl 3)*
> Areas: `billfernyshouse`, `bree`. Bill Ferny: reuse from `bree.git.json`; ruffian impostor — clone any
> `breelocal*`, faction Hostile. On completion: `SetLocalInt(oPC, "ferny_prequel", 1)` — read by Ferny's Ring
> start dialogue (extra discount branch). Journal tag: `ferny_return`. Stages: 1, 2, 3 (`End=1`).

**The Miller's Other Son** *(One-Off, Lvl 8)*
> Areas: `bree`, `tharbadbridge`, `tharbadwest001`, `thardbadeast`. NPCs: miller (reuse), peddler (new commoner
> UTC), cult leader (clone Sauron-cultist Hostile; tag `MillerCultLeader`). Persuade DC 18:
> `if (d20() + GetSkillRank(SKILL_PERSUADE,oPC) >= 18)`. Journal tag: `bree_miller_son2`.

**The Twentieth Plot of Mazarbul** *(One-Off, Lvl 18)*
> Areas: `chamberofrecords`, `balinstomb`, `morialevel1cente`, `theabyssofmoria`. Elrond: `elrond001` (reuse).
> Restless ghost: new UTC, clone commoner with Dwarven undead appearance. Brazier placeables: `OnUsed`
> increments `GetLocalInt(oPC,"crypt_seal")`; on ==3, fight the wraith. Journal tag: `mazarbul_20`.

**The Carn Dûm Ledger** *(Weekly, Lvl 28+)*
> Areas: `carndum`, `carndumcity`, `carndumthrone`, `angmar`. Witch-King: reuse; ledger keeper: new, clone
> `nazgulguildhouse` resident. State var: `SetCampaignInt(GetModule(), "carndum_ledger_pages", n+1)` per
> success — subtracted from Witch-King HP/saves at next encounter. Cooldown: `lastdone_carndum_ledger`.
> Journal tag: `carndum_ledger`.

**Beorn's Garden** *(Daily, Lvl 12+)*
> Areas: `beorn`, `carrok`, `carrokgreater`, `carroklesser`. Beorn NPCs: `bearbeorning001`, `beorning001`,
> `grimbeorntheo001` (reuse). Mechanics: kill 6 wargs (CR 5–7), `ActionUseObject` on 3 `HoneyHive` placeables.
> Cooldown: daily. Journal tag: `beorn_garden`. Reward: randomized from `treasure_beorn` chest.

**The Watcher of Tharbad Bridge** *(One-Off, Lvl 20)*
> Areas: `tharbadbridge`, `thardbadeast`. Watcher boss: clone CEP tentacled creature (`zep_water_tent`).
> State var: `SetCampaignInt(GetModule(), "tharbad_watcher", 0/1/2)`. OnEnter at twilight
> `(GetTimeHour() in [18..21])`: spawn Watcher only if state==0. Journal tag: `tharbad_watcher`.

**The Grey Lord's Errand at Annúminas** *(One-Off, Lvl 38)*
> Areas: `ruinsofannuminas`, `cardolan`, `gravesofthelostk`, `forgottenking`. Aragorn: reuse. King-shades:
> 3 new UTCs, mummy lord chassis + Undead immunities. Success increments `SetLocalInt(oPC, "annuminas_trial", n+1)`;
> on 3, sceptre placeable opens. Journal tag: `annuminas_sceptre`.

**The Empty Throne of Dol Guldur** *(One-Off, Lvl 42)*
> Areas: `dolguldur`, `dolguldur001`, `dolguldurcastle`, `dolguldurcast001`, `cavesofdolguldur`,
> `dolguldursmith`, `dolguldurcity`. Radagast: reuse (Good variant); Sauron-cultist: new (Evil variant).
> Boss: clone `sauronschosen005`, tag `DolguldurShadowPriest`. State var:
> `SetCampaignInt(GetModule(), "dolguldur_throne", n)` (1=consecrated, 2=claimed). Journal tag: `dolguldur_throne`.

**Faramir's Watch** *(Weekly, Lvl 32+)*
> Areas: `hennethannun`, `hennethannun002`, `gondoremynarnen`, `emynarnen`, `emynarnen001`, `harad`,
> `roadtoharad`. Faramir: new UTC, clone Aragorn, retag. Rotation: `GetCalendarDay() / 7 % 3`.
> Cooldown: weekly per-PC. Journal tag: `faramir_watch`.

**The Last Drop at Frogmorton Inn** *(Daily, Lvl 1+)*
> Area: `frogmorton001`. Five existing hobbits in `.git` (rename via dialog references; no new UTCs).
> Correct answer: `GetCalendarMonth()` indexes branch. Cooldown: daily. Journal tag: `frogmorton_ale`.

---

## Prestige-Class Quest Implementation

**Arcane Archer — The Galadhrim's Marker**
> Areas: `lothlorien`, `mirkwoodnorth`, `mirkwoodwest`. Galadriel: reuse. Galadhrim hunter: new UTC.
> Three planted-arrow placeables with `OnUsed` bearing checks. Journal tag: `pc_arcanearcher`.

**Assassin — The Quiet Heir of Carn Dûm**
> Areas: `carndumcity`, `carndumtemple`, `carndumsmithy`. Rival assassin: new UTC (human black, kukri).
> "No witnesses" check: `GetIsPC` + not-in-party creature in area = quest fails. Journal tag: `pc_assassin`.

**Blackguard — The Black Captain's Mark**
> Areas: `nazgulguildhouse`, `bree`, `templeofilluvata`, `thealtar`. Previous bearer: new UTC.
> Alignment shift: `AdjustAlignment(oPC, ALIGNMENT_EVIL, 50)`. Area-tag-gated regen on `OnEquip` script.
> Journal tag: `pc_blackguard`.

**Divine Champion — The Vow Renewed**
> Areas: `minastirith`, `minastirithtemp`, `gondorcrypts`. Chaplain: new commoner; fallen knight: Gondor guard
> clone, alignment Evil, faction Hostile. Journal tag: `pc_divinechampion`.

**Dwarven Defender — The Last Hold of Khazad**
> Areas: `dwarrowdelfea001`, `dwarrowdelfeast`, `morialevel1cente`. Veteran: new UTC, clone dwarf NPC, equip
> waraxe + tower shield. Waves: existing `goblinb001` + troll UTCs. Racial gate:
> `GetRacialType(oPC) == RACIAL_TYPE_DWARF`. Journal tag: `pc_dwarvendef`.

**Harper Scout — The Cipher in the Inn**
> Areas: `theprancingpo001`, `bree`, `rivendell`, `lothlorien`. Three new Harper contact UTCs (commoner,
> distinctive cloaks). Lore-skill conditional in dialogue. Journal tag: `pc_harper`.

**Pale Master — The Twenty-First Tomb**
> Areas: `cryptsofthelosts`, `breecrypt`, `breecryptlowerle`, `deadmarshcrypts`. Thrall boost:
> `OnEquipItem` script that boosts next summon's HP. Reagent check via `GetItemPossessedBy`. Journal tag: `pc_palemaster`.

**Knight of Westernesse — The Banner of the West**
> Areas: `thepelennorfield`, `minastirithgates`, `osgilbridge`. Guardsmen: reuse `guardsofconstant` or
> `bishobofconstant`. Survival count: `SetCampaignInt(... "pdk_command", n, oPC)`. Journal tag: `pc_pdk`.

**Red Dragon Disciple — Smaug's Scale**
> Areas: `theruinsofdale`, `thelonelymountai`, `lonelymountainma`. Dragon-cult survivor: new UTC.
> Will save check: `d20 + GetAbilityModifier(WIS) + base_will >= 18` in dialogue. Journal tag: `pc_rdd`.

**Shadowdancer — Through Shelob's Web Without a Lantern**
> Areas: `shelobslair`, `cirithungol`, `thecirithungolpa`. Shelob: `shelob001.utc.json` (reuse).
> OnAreaEnter strips torch UTIs via `CopyItem`. `OnSpellCastAt` for `SPELL_LIGHT` fails quest.
> Journal tag: `pc_shadowdancer`.

**Shifter — The Skin-Changer's Bargain**
> Areas: `beorn`, `mirkwoodeast`, `carrok`. Skin-changer elder: new UTC, clone Beorn appearance.
> `OnHeartbeat` watches `GetAppearanceType(oPC)`; reverts to PC appearance = quest fails.
> Journal tag: `pc_shifter`.

**Weapon Master — The Duel of Three Hundred**
> Area: `arena001`. Weapon-master: new UTC, kama / kukri / dwarven waraxe. Opening dialogue strips all PC
> weapons via stash, hands chosen exotic; victory restores gear. Journal tag: `pc_weaponmaster`.

---

## Module Compatibility Audit

### Already in the module

- **Most quest area locations.** Bree + sub-locations, Shire, Old Forest, Barrow Downs, Trollshaws,
  Weathertop, Rivendell + Smithy, Moria (full chain through Balrog), Mirkwood (full + Dol Guldur),
  Lothlórien + Flets, Carrock + Beorn, Erebor + Dale, Misty Mountains + Goblin-Town, Carn Dûm / Angmar,
  Cardolan, Rhudaur, Tharbad, Annúminas, Helm's Deep, Dunharrow, Edoras + Theoden's Hall, Pelennor,
  Minas Tirith (gates, houses of healing, temple), Henneth Annûn, Emyn Arnen, Osgiliath, Cirith Ungol +
  Pass, Shelob's Lair, Mount Doom ×2, Black Gate, Dagorlad, Dead Marshes + Crypts, Emyn Muil, Nindalf,
  Mordor entry, Nazgûl Guildhouse, Dark Star Guildhouse.
- **Named NPCs.** Gandalf (`Gandalf`), Saruman (`ms_orth17`, conv `saurman`), Elrond (`Elrond`),
  Aragorn (`AragornSonofArathorn`), Treebeard (`TreeBeard`), Galadriel (`Galadriel`),
  Eowyn (`EowyntheShieldmaiden`), Theoden (`theoden002`), Radagast (`RadagasttheBrown`),
  Bilbo (`BilboBaggins`), Gollum (`Gollum`), Witch-King (`WitchKing`), Legolas (`legolas`),
  Gimli (`gimli`), Beorn (`beorning*`), Shelob (`shelob001`), Balrog (`thebalrog`).
- **Frameworks.** CEP 2, DMFI, DM Wand, Bedlamson Dynamic Merchants, HGLL (Letoscript Lvl 41–60),
  pc_export autosave.
- **Persistence.** Campaign DB via `Get/SetCampaignInt/String/Float` (already used by `bankdb`).
- **Existing journal entries (11).** `p000`, `Bree Millers Son`, `Elrond's Request`, `Feeding Tharbad`,
  `Ferny's Ring`, `Gloison's Heirloom`, `guilds`, `Ruin of Annuminas`, `rules`, `The Well of Souls`,
  `website`. New quests must use new, collision-free tags.
- **Module event hooks.** `Mod_OnHeartbeat = bleeding`, `Mod_OnAcquirItem = acquireditem_tag`,
  `Mod_OnPlrLvlUp = mod_level`, `Mod_OnPlrRest = on_mod_rest`, etc. New quest hooks must chain through
  these scripts — never replace the field directly.

### Partially supported / needs scaffolding

- **Faction granularity.** Only Good/Evil/Neutral globals. Realm-specific reputations need new factions
  in `repute.fac.json` + a rep matrix.
- **Mounts.** Check `Mod_HorseEnabled` in `module.ifo.json`. If off, all ride/mount verbs are flavour only.
- **Player housing.** No instancing. Single shared interior with an `OnAreaEnter` owner-check workaround.
- **Server-wide events.** Implementable via `SetCampaignInt(GetModule(), ...)` but requires daily/weekly tick
  logic added to `bleeding.nss`.
- **Custom item bonuses.** "+8 stat" (stock caps at +12 but recommend ≤ +5), "+N caster level", "Spell DC +N",
  "Sneak Attack +Nd6", "Stunning Fist DC +N" all need substitutes. See per-class notes above.
- **Time-of-day.** `GetTimeHour()` reliable. "30-second Will save" quests must be expressed in heartbeat ticks
  (every 6s), not real seconds.

### Not in the module — would need authoring

- **Areas:** Pelargir, Eagles' Eyrie, Eregion / Ost-in-Edhil, Grey Havens, Bay of Forochel, Nan Dungortheb,
  Rhûn (proper), Brown Lands (substitute `dagorlad`/`nindalf`), Cirith Ungol interior (only the pass exists).
  Each requires `.are` + `.git` + `.gic` and an entry in `module.ifo.json` → `Mod_Area_list`.
- **Named NPCs:** Tom Bombadil, Old Man Willow, Faramir, Haldir, Círdan, Denethor, Boromir, Mouth of Sauron,
  Smaug. All authorable by cloning a similar UTC and editing.
- **Wraith / shade family creatures.** Clone from `mummyboss001` or `lesserbarrowwigh.utc.json`.
- **Quest cooldown helper.** No shared library. Recommend `quest_cd_inc.nss` with:
  `int IsQuestOnCooldown(string sQuest, object oPC, int nDays)` and
  `void StampQuest(string sQuest, object oPC)` — keeps daily/weekly logic out of each script.

### Design notes

- Class questlines intentionally cross zones used by other quests — completing your class line unlocks
  shortcuts and dialogue options in location quests.
- The Isengard tug-of-war (Fangorn daily) and other server-state variables are the backbone of a living-world
  feel. Recommend 6–10 such variables total; all share the same `GetCampaignInt(GetModule(), ...)` mechanism.
- Capstone economy: class capstones sit at Enhancement +5 + typed bonuses (+14/+15 equivalent). Daily/weekly
  rewards should top out around +10–+12 equivalent to preserve capstone prestige. Keep the spread above
  2 raw enhancement points so capstones still feel distinct.
