# Creature drops - elite audit (Loot Overhaul Phase 4)

**Generated** by `python3 bin/loot-sim.py --creatures --write` from `loot/sources.json`
(`creatures`), `loot/levels.json`, `loot/area_levels.json` and the placed creatures in
`unpacked/*.git.json`. Do not hand-edit; re-run after a change. Roadmap: `lo-creature-drops`.

A PC-credited kill of a hostile creature may leave rolled items on its corpse. Its class
decides how often:

| class | rule | drop chance | rolls | rarity floor |
|---|---|---|---|---|
| normal | everything else | 4.0% | 1 | Common |
| elite | CR loot level >= area loot level + **5** (`elite_margin`), or `elite_include` | 25.0% | 1 | Common |
| boss | in the Roll of the Fallen registry (`brd_db.nss`) | 100.0% | 2 (+1 at CR 1000+), + named roll 10% | Epic |

**To tune:** change `elite_margin`, or list a creature resref with a reason in
`elite_include` (always elite), `elite_exclude` (never elite) or `exclude` (never drops), then
`python3 bin/gen-loot-tables.py --apply` and re-run this report. `--margin N` previews another
margin without editing anything.

**Levels are loot levels (1-60), not CRs.** A CR maps to a loot level through
`loot/levels.json` `cr_points`: CR 10 = 8, CR 25 = 19, CR 55 = 31, CR 100 = 35, CR 250 = 45, CR 500 = 48, CR 1000 = 55. An area's loot level is the 50th-percentile CR of
its hostile creatures (`area_percentile`), shown as *area CR*, unless
`sources.json` `area_overrides` pins it.

Normal and elite creatures must be in a hostile faction (reputation toward PCs <= 10, the
area-level rule); registered bosses drop whatever faction they were placed in.

Counting: a *slot* is one placed hostile creature, or one entry in a placed hostile
encounter's creature list. An encounter spawns some of its list, possibly more than once, so
encounter numbers are indicative. *Drops per clear* = expected rolled items from killing every
slot once. *Chest gear per fill* = expected rolled items from opening every loot container
in the area once.

## Margin sweep

| elite_margin | elite slots | % of non-boss | distinct creatures | areas |
|---|---|---|---|---|
| 3 | 755 | 18.2% | 135 | 89 |
| **5** | 494 | 11.9% | 96 | 69 |
| 7 | 367 | 8.9% | 67 | 56 |
| 10 | 198 | 4.8% | 46 | 37 |
| 15 | 93 | 2.2% | 27 | 21 |

## Totals at margin 5

| class | slots | distinct creatures | drops per full clear |
|---|---|---|---|
| normal | 3650 | 400 | 170.8 |
| elite | 494 | 96 | 123.5 |
| boss | 80 | 80 | 184.0 |
| ... of which champions (expected per clear) | 118 | | |
| excluded | 0 | 0 | 0 |

Rarity mix of one roll: normal: Common 56.4% / Uncommon 29.2% / Rare 10.8% / Epic 3.0% / Legendary 0.6%; boss: Epic 97.5% / Legendary 2.5% (elite rolls like normal).

## Elite creatures at margin 5

Grouped by area. *over* = how far the creature's loot level is above the area's.

| area | area CR | area lvl | creature | resref | CR | loot lvl | over | slots | why |
|---|---|---|---|---|---|---|---|---|---|
| Angmar (`angmar`) | 15 | 11 | Tirg the General | `gntfire001` | 53 | 31 | +20 | 1 | auto |
| Angmar (`angmar`) | 15 | 11 | Ologai Troll | `ogreboss001` | 23 | 17 | +6 | 2 | auto |
| Carn Dum (`carndum`) | 35 | 26 | Black Numenorean Archer | `blacknumenorea_2` | 80 | 33 | +7 | 2 | auto |
| Carrok (`carrok`) | 16 | 12 | Carrok Elite Guard | `gntfrost003` | 24 | 18 | +6 | 5 | auto |
| Carrok: Greater (`carrokgreater`) | 13 | 10 | Carrok Elite Guard | `gntfrost003` | 24 | 18 | +8 | 5 | auto |
| Carrok: Lesser (`carroklesser`) | 16 | 12 | Carrok Elite Guard | `gntfrost003` | 24 | 18 | +6 | 4 | auto |
| Dol Guldur City (`dolguldurcity`) | 245 | 45 | Dol - Guldur  Elite Bow Man | `mordororcbowm005` | 658 | 50 | +5 | 5 | auto |
| Dunland (`dunland`) | 8 | 6 | Dunland Shaman | `uthgard006` | 80 | 33 | +27 | 1 | auto |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 11 | 8 | Wilder Chieftain | `bugbearboss006` | 30 | 22 | +14 | 1 | auto |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 11 | 8 | Trollog Devestator | `ogremageboss001` | 21 | 16 | +8 | 3 | auto |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 8 | 6 | Darcara the Cruel | `darcarathecruel` | 26 | 19 | +13 | 1 | auto |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 8 | 6 | Trollog Devestator | `ogremageboss001` | 21 | 16 | +10 | 4 | auto |
| Edoras (`edoras`) | 55 | 31 | Elite Rohirrim Soldier | `arohirrimsold004` | 158 | 41 | +10 | 2 | auto |
| Enchanted Caverns (`enchantedcave002`) | 15 | 11 | Xanith The Mad | `xaniththemad004` | 32 | 24 | +13 | 1 | auto |
| Ered Duath Road: A (`eredduathroada`) | 131 | 38 | Mordor Orc Lieutenant Soldier | `urukai016` | 200 | 45 | +7 | 7 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | zep_dracolich | `zep_dracolich` | 42 | 30 | +25 | 1 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | (missing blueprint) | `nw_lich001` | 28 | 21 | +16 | 1 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | (missing blueprint) | `nw_lich003` | 17 | 13 | +8 | 2 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | (missing blueprint) | `nw_vampire003` | 16 | 12 | +7 | 2 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +5 | 1 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | (missing blueprint) | `nw_vampire002` | 13 | 10 | +5 | 2 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | (missing blueprint) | `nw_vampire004` | 13 | 10 | +5 | 2 | auto |
| Ettenmoors (`ettenmoors`) | 23 | 17 | Uruk Hai First Born | `urukhaifirstborn` | 115 | 37 | +20 | 4 | auto |
| Ettenmoors (`ettenmoors`) | 23 | 17 | Uruk Hai Bowman | `urukaibowman` | 92 | 34 | +17 | 4 | auto |
| Ettenmoors (`ettenmoors`) | 23 | 17 | Uruk Hai Slayer | `urukai012` | 91 | 34 | +17 | 4 | auto |
| Ettenmoors (`ettenmoors`) | 23 | 17 | Uruk Hai Slayer | `urukai014` | 81 | 33 | +16 | 4 | auto |
| Ettenmoors (`ettenmoors`) | 23 | 17 | Ologai Battle Troll | `ogreboss002` | 50 | 30 | +13 | 4 | auto |
| Gap of Rohan (`gapofrohaneast`) | 22.5 | 17 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +14 | 2 | auto |
| Gap of Rohan (`gapofrohaneast`) | 22.5 | 17 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +13 | 2 | auto |
| Gap of Rohan (`gapofrohaneast`) | 22.5 | 17 | Riddermark Guardian | `riddermarkguardi` | 36 | 27 | +10 | 2 | auto |
| Gap of Rohan (`gapofrohaneast`) | 22.5 | 17 | Riddermark Bowman | `riddermarkbowman` | 32 | 24 | +7 | 2 | auto |
| Goblin Gate: Greater (`goblingategreate`) | 5 | 4 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +5 | 2 | auto |
| Goblin Gate: Lesser (`goblingatelesser`) | 3 | 3 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +6 | 1 | auto |
| Goblin Gate: Mines (`goblingatemines`) | 5 | 4 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +5 | 5 | auto |
| Goblin Town: Main Hall (`goblintownmainha`) | 5 | 4 | The Goblin King | `bugbearboss004` | 58 | 31 | +27 | 1 | auto |
| Goblin Town: Main Hall (`goblintownmainha`) | 5 | 4 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +5 | 3 | auto |
| Goblin Town: Main Hall (`goblintownmainha`) | 5 | 4 | Logorul Warmaster | `bugbearboss003` | 12 | 9 | +5 | 1 | auto |
| Goblin Town: Main Hall (`goblintownmainha`) | 5 | 4 | Shargulrul Warmaster | `bugbearboss005` | 12 | 9 | +5 | 1 | auto |
| Goblin Town: Warrens (`goblintownwarren`) | 6 | 5 | Bobo | `goblinb001` | 463 | 48 | +43 | 5 | auto |
| Great East Road (`greateastroadb`) | 6 | 5 | (missing blueprint) | `nw_lich001` | 28 | 21 | +16 | 1 | auto |
| Great East Road (`greateastroadb`) | 6 | 5 | (missing blueprint) | `nw_lich003` | 17 | 13 | +8 | 1 | auto |
| Great East Road (`greateastroadb`) | 6 | 5 | (missing blueprint) | `nw_vampire003` | 16 | 12 | +7 | 1 | auto |
| Great East Road (`greateastroadb`) | 6 | 5 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +5 | 1 | auto |
| Great East Road (`greateastroadb`) | 6 | 5 | (missing blueprint) | `nw_vampire002` | 13 | 10 | +5 | 1 | auto |
| Great East Road (`greateastroadb`) | 6 | 5 | (missing blueprint) | `nw_vampire004` | 13 | 10 | +5 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_humanmerc006` | 15 | 11 | +8 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_elfmerc006` | 14 | 11 | +8 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_dwarfmerc006` | 13 | 10 | +7 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_halfmerc006` | 13 | 10 | +7 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_humanmerc005` | 12 | 9 | +6 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_elfmerc005` | 11 | 8 | +5 | 1 | auto |
| Great East Road (`greateastroadc`) | 3 | 3 | (missing blueprint) | `nw_halfmerc005` | 10 | 8 | +5 | 1 | auto |
| Great East Road (`greateastroadd`) | 52 | 31 | Drider Militia | `drowfight021` | 650 | 50 | +19 | 4 | auto |
| Great East Road (`greateastroadd`) | 52 | 31 | Black Numenorean Assassin | `numenoreanpatrol` | 331 | 46 | +15 | 4 | auto |
| Great North Road (`gondorwesta`) | 32 | 24 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +7 | 3 | auto |
| Great North Road (`gondorwesta`) | 32 | 24 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +6 | 3 | auto |
| Great North Road (`gondorwestb`) | 32 | 24 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +7 | 3 | auto |
| Great North Road (`gondorwestb`) | 32 | 24 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +6 | 3 | auto |
| Great North Road (`greatnorthroad`) | 32 | 24 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +7 | 2 | auto |
| Great North Road (`greatnorthroad`) | 32 | 24 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +6 | 2 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_lich001` | 28 | 21 | +18 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_lich003` | 17 | 13 | +10 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_vampire003` | 16 | 12 | +9 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_humanmerc006` | 15 | 11 | +8 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_slaaddeth` | 15 | 11 | +8 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_elfmerc006` | 14 | 11 | +8 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_dwarfmerc006` | 13 | 10 | +7 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_halfmerc006` | 13 | 10 | +7 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +7 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_vampire002` | 13 | 10 | +7 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_vampire004` | 13 | 10 | +7 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_humanmerc005` | 12 | 9 | +6 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_mohrg` | 12 | 9 | +6 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_vampire001` | 12 | 9 | +6 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_bandit007` | 11 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_diretiger` | 11 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_elfmerc005` | 11 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_gnthill` | 10 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_gntmount` | 10 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_halfmerc005` | 10 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_mumfight` | 10 | 8 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | (missing blueprint) | `nw_slaadgray` | 10 | 8 | +5 | 1 | auto |
| Helm's Deep (`helmsdeep001`) | 145 | 39 | Helm's Deep Elite Guard | `helmsdeepguar003` | 240 | 45 | +6 | 6 | auto |
| House of Nazgûl (`nazgulguildhouse`) | 48 | 30 | Mashano, Messenger To The Witch King | `creature020` | 236 | 45 | +15 | 1 | auto |
| Isengard (Outerrim) (`isengardouterrim`) | 103.5 | 35 | Dunlending Shock Trooper | `uthgard008` | 207 | 45 | +10 | 3 | auto |
| Kallrist Crypt (`kallristcryptlow`) | 12 | 9 | (missing blueprint) | `nw_lich001` | 28 | 21 | +12 | 4 | auto |
| Kallrist Crypt (`kallristcryptupp`) | 12 | 9 | (missing blueprint) | `nw_lich001` | 28 | 21 | +12 | 7 | auto |
| Kallrist Crypt (`kallristcryptupp`) | 12 | 9 | Burning Skeleton | `kallristundead` | 26 | 19 | +10 | 7 | auto |
| Kallrist, East shore (`kallristwestshor`) | 14 | 11 | A Minotaur Warlord | `minotaurwarlord` | 23 | 17 | +6 | 3 | auto |
| Kallrist, Land bridge (`kallristdarkrim`) | 15.5 | 12 | A Minotaur Warlord | `minotaurwarlord` | 23 | 17 | +5 | 3 | auto |
| Kallrist, North shore (`kallristnorthsho`) | 15.5 | 12 | A Minotaur Warlord | `minotaurwarlord` | 23 | 17 | +5 | 7 | auto |
| Loogaz Lair (`loogazlair`) | 3 | 3 | Loogaz | `humanoid_gobl001` | 13 | 10 | +7 | 1 | auto |
| Mering Stream (`meringstream`) | 32 | 24 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +7 | 2 | auto |
| Mering Stream (`meringstream`) | 32 | 24 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +6 | 2 | auto |
| Minas Tirith: City (`minastirith`) | 82 | 33 | Epic Gondorian Guardsman | `gondorianguar002` | 211 | 45 | +12 | 3 | auto |
| Minas Tirith: City (`minastirith`) | 82 | 33 | Gondorian Wizard | `gondorianwizard` | 200 | 45 | +12 | 4 | auto |
| Minas Tirith: Gates (`minastirithgates`) | 82 | 33 | Epic Gondorian Guardsman | `gondorianguar002` | 211 | 45 | +12 | 2 | auto |
| Minas Tirith: Gates (`minastirithgates`) | 82 | 33 | Gondorian Wizard | `gondorianwizard` | 200 | 45 | +12 | 1 | auto |
| Mindalf (`nindalf`) | 28 | 21 | Krenshar | `krenshar` | 41 | 30 | +9 | 3 | auto |
| Mirkwood: Central (`mirkwoodcentral`) | 5 | 4 | Lava Climber | `spidwra001` | 37 | 27 | +23 | 4 | auto |
| Mirkwood: Central (`mirkwoodcentral`) | 5 | 4 | Spider-Queen | `spiderboss001` | 27 | 20 | +16 | 4 | auto |
| Mirkwood: Central (`mirkwoodcentral`) | 5 | 4 | Killer Bees | `killerbees` | 26 | 19 | +15 | 1 | auto |
| Mirkwood: Central (`mirkwoodcentral`) | 5 | 4 | Giant Spider | `spidgiant001` | 21 | 16 | +12 | 4 | auto |
| Mirkwood: Central East (`mirkwoodcentrale`) | 29 | 22 | A Death Weeper Spider | `spidphase001` | 45 | 30 | +8 | 3 | auto |
| Mirkwood: Central East (`mirkwoodcentrale`) | 29 | 22 | Black Spear Spider | `spidswrd001` | 45 | 30 | +8 | 3 | auto |
| Mirkwood: Central South (`mirkwoodcentrals`) | 29 | 22 | A Death Weeper Spider | `spidphase001` | 45 | 30 | +8 | 5 | auto |
| Mirkwood: Central South (`mirkwoodcentrals`) | 29 | 22 | Black Spear Spider | `spidswrd001` | 45 | 30 | +8 | 5 | auto |
| Mirkwood: Dol Guldur (`dolguldur`) | 264 | 45 | Dol Guldur Gate Keeper | `dolguldurgatek_2` | 701 | 51 | +6 | 1 | auto |
| Mirkwood: Dol Guldur (`dolguldur`) | 264 | 45 | Dol Guldur Gate Keeper | `dolguldurgatekee` | 696 | 51 | +6 | 1 | auto |
| Mirkwood: East (`mirkwoodeast`) | 5 | 4 | Lava Climber | `spidwra001` | 37 | 27 | +23 | 4 | auto |
| Mirkwood: East (`mirkwoodeast`) | 5 | 4 | Spider-Queen | `spiderboss001` | 27 | 20 | +16 | 4 | auto |
| Mirkwood: East (`mirkwoodeast`) | 5 | 4 | Giant Spider | `spidgiant001` | 21 | 16 | +12 | 4 | auto |
| Mirkwood: North (`mirkwoodnorth`) | 29 | 22 | A Death Weeper Spider | `spidphase001` | 45 | 30 | +8 | 3 | auto |
| Mirkwood: North (`mirkwoodnorth`) | 29 | 22 | Black Spear Spider | `spidswrd001` | 45 | 30 | +8 | 3 | auto |
| Mirkwood: West (`mirkwoodwest`) | 5 | 4 | Lava Climber | `spidwra001` | 37 | 27 | +23 | 5 | auto |
| Mirkwood: West (`mirkwoodwest`) | 5 | 4 | Spider-Queen | `spiderboss001` | 27 | 20 | +16 | 5 | auto |
| Mirkwood: West (`mirkwoodwest`) | 5 | 4 | Giant Spider | `spidgiant001` | 21 | 16 | +12 | 5 | auto |
| Morannon - The Black Gate (`blackgatge`) | 136 | 39 | Gate Giant | `gategiant001_2` | 221 | 45 | +6 | 4 | auto |
| Morannon - The Black Gate (`blackgatge`) | 136 | 39 | Gate Shaman - Mordor Black Gate | `creature001_2` | 212 | 45 | +6 | 2 | auto |
| Moria Level 1 (Center) (`morialevel1cente`) | 10 | 8 | Trollog Devestator | `ogremageboss001` | 21 | 16 | +8 | 3 | auto |
| Plane of the Render (`planeoftherender`) | 17 | 13 | Raitheen the Watcher | `raitheen` | 60 | 31 | +18 | 1 | auto |
| Plane of the Render (`planeoftherender`) | 17 | 13 | Render the Mammoth Watcher | `grayrend001` | 40 | 30 | +17 | 1 | auto |
| Plane of the Render (`planeoftherender`) | 17 | 13 | Grokul Head Master | `minchief001` | 24 | 18 | +5 | 1 | auto |
| Ruins of Annuminas (`ruinsofannuminas`) | 16 | 12 | Azagoth | `azagoth` | 37 | 27 | +15 | 1 | auto |
| Ruins of Annuminas (`ruinsofannuminas`) | 16 | 12 | (missing blueprint) | `x2_golem002` | 32 | 24 | +12 | 7 | auto |
| Sharkey's Chamber (`sharkeyschamber`) | 1 | 1 | Smithey the Sneak | `halfmerc002` | 13 | 10 | +9 | 1 | auto |
| Sharkey's Chamber (`sharkeyschamber`) | 1 | 1 | Groodok the Skinner | `bandit007` | 7 | 6 | +5 | 1 | auto |
| Temple of Nazgul (`area010`) | 75 | 33 | Nazgul | `thundergut` | 255 | 45 | +12 | 1 | auto |
| Temple of Nazgul (`area010`) | 75 | 33 | Great Black Dragon | `epicblackdragon` | 126 | 38 | +5 | 2 | auto |
| The Abyss of Moria (`theabyssofmoria`) | 37 | 27 | Massive Bombardier Beetle | `btlbomb001` | 73 | 33 | +6 | 5 | auto |
| The Abyss of Moria (`theabyssofmoria`) | 37 | 27 | Servator of the Abyss | `yuan_ti004` | 69 | 32 | +5 | 4 | auto |
| The Abyss of Moria (`theabyssofmoria`) | 37 | 27 | Lava Life Walker | `fireelder001` | 65 | 32 | +5 | 4 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 20 | 15 | Drider Militia | `drowfight021` | 650 | 50 | +35 | 2 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 20 | 15 | Black Numenorean Assassin | `numenoreanpatrol` | 331 | 46 | +31 | 2 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 20 | 15 | Black Numenorean Archer | `blacknumenoreana` | 80 | 33 | +18 | 2 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 20 | 15 | Black Numenorean Shadow Master | `drowrogue021` | 52 | 31 | +16 | 2 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 20 | 15 | Black Numenorean Mage | `drowmage002` | 50 | 30 | +15 | 2 | auto |
| The Barrow Downs (`thebarrowdowns`) | 4 | 3 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +7 | 9 | auto |
| The Dimrill Stair (`thedimrillstair`) | 7.5 | 6 | Sarumon's Personal Guard | `urukai` | 267 | 45 | +39 | 1 | auto |
| The Misty Mountains (`mistymountainsa`) | 6 | 5 | A Misty Mountains Giant | `mgiant` | 17 | 13 | +8 | 6 | auto |
| The Misty Mountains (`mistymountainsb`) | 7 | 6 | A Misty Mountains Giant | `mgiant` | 17 | 13 | +7 | 4 | auto |
| The Pelennor Fields (`thepelennorfield`) | 32 | 24 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +7 | 3 | auto |
| The Pelennor Fields (`thepelennorfield`) | 32 | 24 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +6 | 3 | auto |
| The Ruins of Dale (`theruinsofdale`) | 1 | 1 | Gerrey Halliams | `gerrey` | 17 | 13 | +12 | 1 | auto |
| The Secret Pass of Mordor (`thesecretpassofm`) | 4 | 3 | Mordor Orc Lieutenant Soldier | `urukai016` | 200 | 45 | +42 | 1 | auto |
| The Secret Pass of Mordor (`thesecretpassofm`) | 4 | 3 | Mordor Orc Warrior Soldier | `mordororcwarrior` | 50 | 30 | +27 | 1 | auto |
| The Secret Pass of Mordor (`thesecretpassofm`) | 4 | 3 | Mordor Orc Scout Soldier | `urukai_2` | 16 | 12 | +9 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 4 | 3 | (missing blueprint) | `nw_lich003` | 17 | 13 | +10 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 4 | 3 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +8 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 4 | 3 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +7 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 4 | 3 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +7 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 4 | 3 | (missing blueprint) | `nw_doomkght` | 10 | 8 | +5 | 1 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 4 | 3 | (missing blueprint) | `nw_lich003` | 17 | 13 | +10 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 4 | 3 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +8 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 4 | 3 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +7 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 4 | 3 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +7 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 4 | 3 | (missing blueprint) | `nw_doomkght` | 10 | 8 | +5 | 5 | auto |
| Tomb of Peran (`tombofperan`) | 4 | 3 | (missing blueprint) | `nw_lich003` | 17 | 13 | +10 | 4 | auto |
| Tomb of Peran (`tombofperan`) | 4 | 3 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +8 | 4 | auto |
| Tomb of Peran (`tombofperan`) | 4 | 3 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +7 | 4 | auto |
| Tomb of Peran (`tombofperan`) | 4 | 3 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +7 | 4 | auto |
| Tomb of Peran (`tombofperan`) | 4 | 3 | (missing blueprint) | `nw_doomkght` | 10 | 8 | +5 | 4 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | (missing blueprint) | `nw_lich001` | 28 | 21 | +18 | 1 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | Rukor the Summoner | `rukorthesummoner` | 28 | 21 | +18 | 1 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | (missing blueprint) | `nw_lich003` | 17 | 13 | +10 | 9 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +8 | 9 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +7 | 9 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +7 | 9 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | (missing blueprint) | `nw_doomkght` | 10 | 8 | +5 | 9 | auto |
| Tower of Orthanc (`toweroforthanc`) | 78.5 | 33 | Dunlending Shock Trooper | `uthgard008` | 200 | 45 | +12 | 2 | auto |
| Wold North (`thewold`) | 14 | 11 | Krenshar | `krenshar` | 41 | 30 | +19 | 5 | auto |
| Wold North (`thewold`) | 14 | 11 | Malar Panther | `malarpanther` | 30 | 22 | +11 | 5 | auto |
| Wold North (`thewold`) | 14 | 11 | Old Dire Bear | `beardireboss001` | 26 | 19 | +8 | 5 | auto |
| Wold South (`woldsouth`) | 14 | 11 | Krenshar | `krenshar` | 41 | 30 | +19 | 6 | auto |
| Wold South (`woldsouth`) | 14 | 11 | Malar Panther | `malarpanther` | 30 | 22 | +11 | 6 | auto |
| Wold South (`woldsouth`) | 14 | 11 | Old Dire Bear | `beardireboss001` | 26 | 19 | +8 | 6 | auto |

## Champions

A normal creature may spawn as a champion: 'Elite' name prefix, a glow, +100% hit points, +4 attack, +2 damage, +4 AC, +4 saves, and the elite drop chance. Its CR rises by what the toolset formula's hit-point term pays for the extra HP (so XP and drop level follow). Kills count under the base creature in the bestiary, with a separate champion tally.

Chance per spawn: 5.0% in an area with no natural elites, falling linearly with the area's natural elite share to 1.0% at 25% elites, never lower.

| champion chance | areas |
|---|---|
| 5.0% | 108 |
| 4.6% | 1 |
| 4.4% | 1 |
| 4.1% | 1 |
| 3.9% | 1 |
| 3.7% | 1 |
| 3.5% | 2 |
| 3.4% | 3 |
| 3.1% | 1 |
| 3.0% | 1 |
| 2.8% | 3 |
| 2.7% | 1 |
| 2.6% | 2 |
| 2.5% | 4 |
| 2.3% | 1 |
| 2.1% | 3 |
| 2.0% | 1 |
| 1.8% | 2 |
| 1.7% | 1 |
| 1.6% | 3 |
| 1.2% | 3 |
| 1.0% | 33 |

Areas below the base chance:

| area | natural elites / slots | champion chance |
|---|---|---|
| Angmar (`angmar`) | 3 / 13 | 1.0% |
| Carn Dum (`carndum`) | 2 / 6 | 1.0% |
| Enchanted Caverns (`enchantedcave002`) | 1 / 5 | 1.0% |
| Ered Duath Road: A (`eredduathroada`) | 7 / 35 | 1.0% |
| Esgaroth Crypts (`cryptsofthelosts`) | 11 / 53 | 1.0% |
| Ettenmoors (`ettenmoors`) | 20 / 44 | 1.0% |
| Gap of Rohan (`gapofrohaneast`) | 8 / 24 | 1.0% |
| Great East Road (`greateastroadd`) | 8 / 28 | 1.0% |
| Great North Road (`gondorwesta`) | 6 / 21 | 1.0% |
| Great North Road (`gondorwestb`) | 6 / 21 | 1.0% |
| Great North Road (`greatnorthroad`) | 4 / 14 | 1.0% |
| Helm's Deep (`helmsdeep001`) | 6 / 21 | 1.0% |
| Isengard (Outerrim) (`isengardouterrim`) | 3 / 13 | 1.0% |
| Kallrist Crypt (`kallristcryptupp`) | 14 / 66 | 1.0% |
| Mering Stream (`meringstream`) | 4 / 14 | 1.0% |
| Minas Tirith: City (`minastirith`) | 7 / 24 | 1.0% |
| Mindalf (`nindalf`) | 3 / 12 | 1.0% |
| Mirkwood: Central (`mirkwoodcentral`) | 13 / 37 | 1.0% |
| Mirkwood: Central East (`mirkwoodcentrale`) | 6 / 15 | 1.0% |
| Mirkwood: Central South (`mirkwoodcentrals`) | 10 / 25 | 1.0% |
| Mirkwood: East (`mirkwoodeast`) | 12 / 36 | 1.0% |
| Mirkwood: North (`mirkwoodnorth`) | 6 / 15 | 1.0% |
| Mirkwood: West (`mirkwoodwest`) | 15 / 45 | 1.0% |
| Ruins of Annuminas (`ruinsofannuminas`) | 8 / 23 | 1.0% |
| Temple of Nazgul (`area010`) | 3 / 7 | 1.0% |
| The Abyss of Moria (`theabyssofmoria`) | 13 / 29 | 1.0% |
| The Angmar Mountain Range (`theangmarmountai`) | 10 / 27 | 1.0% |
| The Pelennor Fields (`thepelennorfield`) | 6 / 21 | 1.0% |
| Tomb of Peran (`tombofperan`) | 20 / 94 | 1.0% |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 47 / 208 | 1.0% |
| Tower of Orthanc (`toweroforthanc`) | 2 / 5 | 1.0% |
| Wold North (`thewold`) | 15 / 75 | 1.0% |
| Wold South (`woldsouth`) | 18 / 90 | 1.0% |
| Carrok (`carrok`) | 5 / 26 | 1.2% |
| Carrok: Lesser (`carroklesser`) | 4 / 21 | 1.2% |
| Morannon - The Black Gate (`blackgatge`) | 6 / 32 | 1.2% |
| Dol Guldur City (`dolguldurcity`) | 5 / 29 | 1.6% |
| Goblin Town: Main Hall (`goblintownmainha`) | 6 / 35 | 1.6% |
| Greenway (South) (`greenwaysouth`) | 22 / 130 | 1.6% |
| Minas Tirith: Gates (`minastirithgates`) | 3 / 18 | 1.7% |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 4 / 25 | 1.8% |
| Tomb of Mendegilath (`tombofmendegilat`) | 25 / 156 | 1.8% |
| Carrok: Greater (`carrokgreater`) | 5 / 33 | 2.0% |
| Edoras (`edoras`) | 2 / 14 | 2.1% |
| House of Nazgûl (`nazgulguildhouse`) | 1 / 7 | 2.1% |
| Mirkwood: Dol Guldur (`dolguldur`) | 2 / 14 | 2.1% |
| Great East Road (`greateastroadc`) | 7 / 51 | 2.3% |
| Kallrist, Land bridge (`kallristdarkrim`) | 3 / 24 | 2.5% |
| Kallrist, North shore (`kallristnorthsho`) | 7 / 56 | 2.5% |
| Moria Level 1 (Center) (`morialevel1cente`) | 3 / 24 | 2.5% |
| The Misty Mountains (`mistymountainsb`) | 4 / 32 | 2.5% |
| Great East Road (`greateastroadb`) | 6 / 50 | 2.6% |
| Sharkey's Chamber (`sharkeyschamber`) | 2 / 17 | 2.6% |
| Goblin Town: Warrens (`goblintownwarren`) | 5 / 44 | 2.7% |
| Kallrist, East shore (`kallristwestshor`) | 3 / 27 | 2.8% |
| The Ruins of Dale (`theruinsofdale`) | 1 / 9 | 2.8% |
| The Secret Pass of Mordor (`thesecretpassofm`) | 3 / 27 | 2.8% |
| The Dimrill Stair (`thedimrillstair`) | 1 / 10 | 3.0% |
| The Misty Mountains (`mistymountainsa`) | 6 / 63 | 3.1% |
| Goblin Gate: Mines (`goblingatemines`) | 5 / 64 | 3.4% |
| Plane of the Render (`planeoftherender`) | 3 / 38 | 3.4% |
| Tomb of Garmir (`tombofgarmir`) | 5 / 62 | 3.4% |
| Kallrist Crypt (`kallristcryptlow`) | 4 / 52 | 3.5% |
| The Barrow Downs (`thebarrowdowns`) | 9 / 117 | 3.5% |
| Dunland (`dunland`) | 1 / 15 | 3.7% |
| Goblin Gate: Greater (`goblingategreate`) | 2 / 37 | 3.9% |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 5 / 107 | 4.1% |
| Goblin Gate: Lesser (`goblingatelesser`) | 1 / 35 | 4.4% |
| Loogaz Lair (`loogazlair`) | 1 / 50 | 4.6% |

## Drops per area

Areas with hostile creatures, by drops per clear (highest first, champions included).

| area | area CR | lvl | slots | elite | boss | drops per clear | chest gear per fill |
|---|---|---|---|---|---|---|---|
| Tomb of Vinyalonde (`tombofvinyalonde`) | 4 | 3 | 208 | 47 | 0 | 18.53 | 50.70 |
| Tomb of Mendegilath (`tombofmendegilat`) | 4 | 3 | 156 | 25 | 0 | 11.99 | 38.70 |
| Greenway (South) (`greenwaysouth`) | 4 | 3 | 130 | 22 | 0 | 10.18 | 1.20 |
| Tomb of Peran (`tombofperan`) | 4 | 3 | 94 | 20 | 0 | 8.12 | 24.00 |
| Wold South (`woldsouth`) | 14 | 11 | 90 | 18 | 0 | 7.53 | 8.10 |
| The Barrow Downs (`thebarrowdowns`) | 4 | 3 | 117 | 9 | 0 | 7.36 | 0.00 |
| Morannon - The Black Gate (`blackgatge`) | 136 | 39 | 34 | 6 | 2 | 6.81 | 0.00 |
| Dol Guldur City (`dolguldurcity`) | 245 | 45 | 31 | 5 | 2 | 6.49 | 0.00 |
| Wold North (`thewold`) | 14 | 11 | 75 | 15 | 0 | 6.28 | 13.80 |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 8 | 6 | 107 | 5 | 0 | 6.21 | 31.50 |
| Weather Top's Hidden Court (`area028`) | 3250 | 56 | 2 | 0 | 2 | 6.20 | 0.00 |
| Ettenmoors (`ettenmoors`) | 23 | 17 | 44 | 20 | 0 | 6.01 | 0.00 |
| Kallrist Crypt (`kallristcryptupp`) | 12 | 9 | 66 | 14 | 0 | 5.69 | 0.60 |
| Minas Tirith: Gates (`minastirithgates`) | 82 | 33 | 20 | 3 | 2 | 5.60 | 0.00 |
| Minas Tirith: City (`minastirith`) | 82 | 33 | 25 | 7 | 1 | 5.57 | 0.00 |
| Kallrist Crypt (`kallristcryptlow`) | 12 | 9 | 53 | 4 | 1 | 5.37 | 18.90 |
| Edoras (`edoras`) | 55 | 31 | 16 | 2 | 2 | 5.23 | 3.00 |
| Mirkwood: West (`mirkwoodwest`) | 5 | 4 | 45 | 15 | 0 | 5.01 | 0.00 |
| Orc Armory (`orcarmory`) | 200 | 45 | 15 | 0 | 2 | 4.86 | 1.20 |
| Helm's Deep: Keep (`area008`) | 296 | 46 | 14 | 0 | 2 | 4.81 | 9.80 |
| Isengard (Innerrim) (`isengardinnerrim`) | 207 | 45 | 11 | 0 | 2 | 4.65 | 0.00 |
| The Halls of Truth (`halloftruth`) | 78.5 | 33 | 10 | 0 | 2 | 4.60 | 0.00 |
| Esgaroth Crypts (`cryptsofthelosts`) | 6 | 5 | 53 | 11 | 0 | 4.52 | 33.60 |
| Rivendell Upper Halls (`rivendellupperha`) | 158.5 | 41 | 6 | 0 | 2 | 4.40 | 0.00 |
| Mirkwood: Central (`mirkwoodcentral`) | 5 | 4 | 37 | 13 | 0 | 4.26 | 0.00 |
| Helm's Deep (`helmsdeep001`) | 145 | 39 | 22 | 6 | 1 | 4.23 | 0.00 |
| Minas Tirith: Watchman Defender's Head Quarters (`watchmandefender`) | 82.5 | 33 | 2 | 0 | 2 | 4.20 | 0.00 |
| Tower of Orthanc: Saruman's Chambers (`towerofothancsar`) | - | 0 | 2 | 0 | 2 | 4.20 | 0.00 |
| The Misty Mountains (`mistymountainsa`) | 6 | 5 | 63 | 6 | 0 | 4.15 | 6.30 |
| Goblin Gate: Mines (`goblingatemines`) | 5 | 4 | 64 | 5 | 0 | 4.03 | 28.20 |
| Mirkwood: East (`mirkwoodeast`) | 5 | 4 | 36 | 12 | 0 | 4.01 | 0.00 |
| Mirkwood: Central East (`mirkwoodcentrale`) | 29 | 22 | 16 | 6 | 1 | 3.98 | 0.00 |
| Kallrist, North shore (`kallristnorthsho`) | 15.5 | 12 | 56 | 7 | 0 | 3.97 | 0.00 |
| Tomb of Garmir (`tombofgarmir`) | 4 | 3 | 62 | 5 | 0 | 3.94 | 4.80 |
| The Abyss of Moria (`theabyssofmoria`) | 37 | 27 | 29 | 13 | 0 | 3.92 | 0.00 |
| Great East Road (`greateastroadc`) | 3 | 3 | 51 | 7 | 0 | 3.72 | 0.00 |
| Bree Crypt (`breecrypt`) | 3 | 3 | 73 | 0 | 0 | 3.69 | 5.40 |
| The Trollshaws (`thetrollshalls`) | 7 | 6 | 32 | 0 | 1 | 3.67 | 0.00 |
| Dimholt: The Forgotten King (`forgottenking`) | 42 | 30 | 12 | 0 | 1 | 3.66 | 0.00 |
| Helm's Deep: Cave (`area013`) | 344 | 46 | 12 | 0 | 1 | 3.66 | 0.00 |
| Mount Doom: Halls of Sauron  (`area016`) | 410 | 47 | 12 | 0 | 1 | 3.66 | 0.00 |
| Lothlorien: Main (`lothlorien`) | 176 | 42 | 30 | 0 | 1 | 3.56 | 0.00 |
| Mount Gundabad (`mountgundabadlev`) | 50 | 30 | 29 | 0 | 1 | 3.51 | 33.60 |
| Minas Tirith: Keep (`area005`) | 288 | 46 | 9 | 0 | 1 | 3.50 | 3.60 |
| Númenor:  Noirinan (`falseheaven`) | 1028 | 55 | 9 | 0 | 1 | 3.50 | 3.00 |
| Great East Road (`greateastroadb`) | 6 | 5 | 50 | 6 | 0 | 3.50 | 0.00 |
| Rhosgobel:  Tower (`rhosgobeltower`) | 658 | 50 | 5 | 0 | 1 | 3.30 | 0.00 |
| Isengard (Outerrim) (`isengardouterrim`) | 103.5 | 35 | 14 | 3 | 1 | 3.27 | 0.00 |
| Gwathdor:  Throne of the Lord (`gwaththrone`) | 246 | 45 | 4 | 0 | 1 | 3.25 | 0.00 |
| The Witch King's Throne (`thewitchkingsthr`) | 65 | 32 | 4 | 0 | 1 | 3.25 | 0.00 |
| The Angmar Mountain Range (`theangmarmountai`) | 20 | 15 | 27 | 10 | 0 | 3.22 | 0.00 |
| Mirkwood: Dol Guldur (`dolguldur`) | 264 | 45 | 15 | 2 | 1 | 3.13 | 8.40 |
| Mirkwood: Central South (`mirkwoodcentrals`) | 29 | 22 | 25 | 10 | 0 | 3.13 | 0.00 |
| Gollum's Chambers (`area007`) | 1029 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| Hobbiton (`shirehobbiton001`) | - | 3 | 1 | 0 | 1 | 3.10 | 3.60 |
| Mirkwoods - Halls of Greenleafs (`area023`) | 1418 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| The Ruins of Dale: Cavern (`darkcavern`) | 1048 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| Tower of the High Wizard: The High Wizard's Chamber (`towerofthehighwi`) | 1795 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| Goblin Town: Warrens (`goblintownwarren`) | 6 | 5 | 44 | 5 | 0 | 3.03 | 4.80 |
| Ered Duath Road: A (`eredduathroada`) | 131 | 38 | 35 | 7 | 0 | 2.93 | 4.80 |
| Great East Road (`greateastroadd`) | 52 | 31 | 28 | 8 | 0 | 2.84 | 0.00 |
| Carn Dum (`carndum`) | 35 | 26 | 7 | 2 | 1 | 2.77 | 0.00 |
| Goblin Town: Main Hall (`goblintownmainha`) | 5 | 4 | 35 | 6 | 0 | 2.76 | 32.10 |
| The Valley of Rivendell (`thevalleyofriven`) | 215 | 45 | 14 | 0 | 1 | 2.76 | 0.00 |
| Tower of Orthanc (`toweroforthanc`) | 78.5 | 33 | 6 | 2 | 1 | 2.73 | 0.00 |
| Lonely Mountain: Main Hall (`lonelymountainma`) | 55 | 31 | 13 | 0 | 1 | 2.71 | 0.00 |
| Shelob's Lair (`shelobslair`) | 168 | 42 | 13 | 0 | 1 | 2.71 | 7.20 |
| Loogaz Lair (`loogazlair`) | 3 | 3 | 50 | 1 | 0 | 2.68 | 20.40 |
| Gap of Rohan (`gapofrohaneast`) | 22.5 | 17 | 24 | 8 | 0 | 2.67 | 0.00 |
| Carn Dum: City (`carndumcity`) | 37.5 | 28 | 12 | 0 | 1 | 2.66 | 0.00 |
| Caves of Dol Guldur (`cavesofdolguldur`) | 264 | 45 | 12 | 0 | 1 | 2.66 | 8.40 |
| Ruins of Annuminas (`ruinsofannuminas`) | 16 | 12 | 23 | 8 | 0 | 2.63 | 12.00 |
| Carn Dum: Temple (`carndumtemple`) | 50.5 | 30 | 10 | 0 | 1 | 2.55 | 0.00 |
| Beorn (`beorn`) | 53 | 31 | 9 | 0 | 1 | 2.50 | 0.00 |
| Rivendell (`rivendell`) | 215 | 45 | 9 | 0 | 1 | 2.50 | 0.00 |
| Carrok: Greater (`carrokgreater`) | 13 | 10 | 33 | 5 | 0 | 2.49 | 33.60 |
| Carn Dum: Throne (`carndumthrone`) | 68 | 32 | 8 | 0 | 1 | 2.45 | 0.00 |
| Kerufall's Lair (`kerufallslair`) | 102 | 35 | 8 | 0 | 1 | 2.45 | 0.00 |
| Lothlorien: Flets (`lothlorienflets`) | 102 | 35 | 8 | 0 | 1 | 2.45 | 0.00 |
| Theoden's Hall (`theodenshall`) | 55 | 31 | 8 | 0 | 1 | 2.45 | 0.00 |
| Isengard (Magic Room) (`isengardmagicroo`) | 116 | 37 | 7 | 0 | 1 | 2.40 | 0.00 |
| Osgiliath: Citidal of the Stars (`citidelofstars`) | 190 | 44 | 7 | 0 | 1 | 2.40 | 0.00 |
| Temple of Marr (`thehallsoftruth`) | 55 | 31 | 7 | 0 | 1 | 2.40 | 0.00 |
| Plane of the Render (`planeoftherender`) | 17 | 13 | 38 | 3 | 0 | 2.40 | 0.00 |
| Angmar's Lair (`area009`) | 548.5 | 49 | 6 | 0 | 1 | 2.35 | 0.00 |
| Emyn Arnen: Peak (`emynarnen`) | 18 | 14 | 6 | 0 | 1 | 2.35 | 0.00 |
| Nîn-in-Eilph (`cardolan`) | 8 | 6 | 45 | 0 | 0 | 2.27 | 0.00 |
| The Misty Mountains (`mistymountainsb`) | 7 | 6 | 32 | 4 | 0 | 2.27 | 1.20 |
| The Temple of Morannon (`thetempleofmoran`) | 7 | 6 | 4 | 0 | 1 | 2.25 | 0.00 |
| Dol Guldur:  Tower Of Black Magic Depths (`dolguldurcast001`) | 551 | 49 | 3 | 0 | 1 | 2.20 | 0.00 |
| Mirkwood: Thranduil's Hall (`thranduilshall`) | 157 | 40 | 3 | 0 | 1 | 2.20 | 7.50 |
| Tower of the High Wizard: The Library (`towerofthehig001`) | 129 | 38 | 3 | 0 | 1 | 2.20 | 0.00 |
| Goblin Gate: Greater (`goblingategreate`) | 5 | 4 | 37 | 2 | 0 | 2.19 | 0.00 |
| Carrok (`carrok`) | 16 | 12 | 26 | 5 | 0 | 2.14 | 0.00 |
| Great North Road (`gondorwesta`) | 32 | 24 | 21 | 6 | 0 | 2.13 | 0.00 |
| Great North Road (`gondorwestb`) | 32 | 24 | 21 | 6 | 0 | 2.13 | 0.00 |
| The Pelennor Fields (`thepelennorfield`) | 32 | 24 | 21 | 6 | 0 | 2.13 | 0.00 |
| Balin's Tomb (`balinstomb`) | 132 | 38 | 1 | 0 | 1 | 2.10 | 0.00 |
| Barad-Dûr: Keep (`baraddurkeep`) | - | 0 | 1 | 0 | 1 | 2.10 | 0.00 |
| Bywater (`bywater`) | - | 0 | 1 | 0 | 1 | 2.10 | 0.00 |
| Carn Dum: Numerok's Den (`area078`) | 130 | 38 | 1 | 0 | 1 | 2.10 | 1.20 |
| Dol Guldur:  Tower Of Black Magic  Nazgul Quaters (`area031`) | 965 | 54 | 1 | 0 | 1 | 2.10 | 0.00 |
| Gwathdor:  Tomb (`gwathtomb`) | 280 | 46 | 1 | 0 | 1 | 2.10 | 0.00 |
| Ice Queen: Nest (`icequeennest`) | 133 | 38 | 1 | 0 | 1 | 2.10 | 27.30 |
| Minas Tirith: Temple (`minastirithtemp`) | 447 | 48 | 1 | 0 | 1 | 2.10 | 0.00 |
| Mirkwood: Crypt Chamber (`area003`) | 564 | 49 | 1 | 0 | 1 | 2.10 | 0.00 |
| Moria: The Balrog of Moria (`thebalrogofmoria`) | 555 | 49 | 1 | 0 | 1 | 2.10 | 0.00 |
| Valinor: Realm of the spirits (`area022`) | 650 | 50 | 1 | 0 | 1 | 2.10 | 0.00 |
| The North Downs (`thenorthdowns001`) | 3 | 3 | 40 | 0 | 0 | 2.02 | 0.00 |
| Goblin Gate: Lesser (`goblingatelesser`) | 3 | 3 | 35 | 1 | 0 | 1.92 | 31.80 |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 11 | 8 | 25 | 4 | 0 | 1.92 | 0.00 |
| Mirkwood: North (`mirkwoodnorth`) | 29 | 22 | 15 | 6 | 0 | 1.88 | 0.00 |
| Midgewater Swamp (`midgewaterswamp`) | 2 | 2 | 37 | 0 | 0 | 1.87 | 7.20 |
| Kallrist, East shore (`kallristwestshor`) | 14 | 11 | 27 | 3 | 0 | 1.85 | 0.00 |
| The Secret Pass of Mordor (`thesecretpassofm`) | 4 | 3 | 27 | 3 | 0 | 1.85 | 0.00 |
| Chamber of Records Wlkwy (`chamberofrecords`) | 7 | 6 | 36 | 0 | 0 | 1.82 | 0.00 |
| Enchanted Caverns (`enchantedcave001`) | 12.5 | 10 | 36 | 0 | 0 | 1.82 | 0.00 |
| Carrok: Lesser (`carroklesser`) | 16 | 12 | 21 | 4 | 0 | 1.72 | 16.80 |
| Kallrist, Land bridge (`kallristdarkrim`) | 15.5 | 12 | 24 | 3 | 0 | 1.70 | 0.00 |
| Moria Level 1 (Center) (`morialevel1cente`) | 10 | 8 | 24 | 3 | 0 | 1.70 | 16.80 |
| Bree Caverns (`breecaverns`) | 3 | 3 | 32 | 0 | 0 | 1.62 | 36.60 |
| Gwathdor:  West Deeps (`gwathwest`) | 238 | 45 | 31 | 0 | 0 | 1.57 | 4.20 |
| Great North Road (`greatnorthroad`) | 32 | 24 | 14 | 4 | 0 | 1.42 | 0.00 |
| Mering Stream (`meringstream`) | 32 | 24 | 14 | 4 | 0 | 1.42 | 0.00 |
| Angmar Dungeon (`angmardungeon`) | 442 | 48 | 28 | 0 | 0 | 1.41 | 16.80 |
| Dead Marshes (`deadmarshes`) | 174 | 42 | 27 | 0 | 0 | 1.36 | 0.00 |
| Great East Road (`greateastroada`) | 3 | 3 | 26 | 0 | 0 | 1.31 | 0.00 |
| Fornost (West) (`area004`) | 5 | 4 | 25 | 0 | 0 | 1.26 | 0.00 |
| Celeduin Banks (`celeduinbanks`) | 5.5 | 4 | 24 | 0 | 0 | 1.21 | 0.00 |
| Chetwood (`chetwood001`) | 3 | 3 | 24 | 0 | 0 | 1.21 | 0.00 |
| Dimholt: The Gate of the Dead (`area018`) | 58 | 31 | 24 | 0 | 0 | 1.21 | 0.00 |
| Mount Doom: Lower Caverns (`mountdoom002`) | 142 | 39 | 24 | 0 | 0 | 1.21 | 0.00 |
| Sharkey's Chamber (`sharkeyschamber`) | 1 | 1 | 17 | 2 | 0 | 1.18 | 20.10 |
| Angmar (`angmar`) | 15 | 11 | 13 | 3 | 0 | 1.17 | 0.00 |
| Númenor:  Arnenelos (`heavensdisdain`) | 1028 | 55 | 23 | 0 | 0 | 1.16 | 0.00 |
| Mindalf (`nindalf`) | 28 | 21 | 12 | 3 | 0 | 1.13 | 0.00 |
| Emyn Muil (`emynmuil`) | 62 | 32 | 21 | 0 | 0 | 1.06 | 0.00 |
| Bree Cave (`breecave`) | 0.33 | 1 | 20 | 0 | 0 | 1.01 | 31.20 |
| Bree Crypt Lower Level (`breecryptlowerle`) | 3 | 3 | 20 | 0 | 0 | 1.01 | 0.00 |
| Dunland War Party (`dunlandwarparty`) | 5.5 | 4 | 20 | 0 | 0 | 1.01 | 16.20 |
| Ice Queen: Lair (`icequeenlair`) | 21.5 | 16 | 20 | 0 | 0 | 1.01 | 0.00 |
| Mount Gundabad Level 2 (`mountgundabad001`) | 50 | 30 | 20 | 0 | 0 | 1.01 | 12.60 |
| Dunland (`dunland`) | 8 | 6 | 15 | 1 | 0 | 0.92 | 0.00 |
| Temple of Nazgul (`area010`) | 75 | 33 | 7 | 3 | 0 | 0.92 | 0.00 |
| Durin's Bridge (`durinsbridge`) | 7 | 6 | 18 | 0 | 0 | 0.91 | 0.00 |
| Old Forest Road (`oldforestroad`) | 9 | 7 | 18 | 0 | 0 | 0.91 | 0.00 |
| Greenway (SouthEast) (`greenwaysoutheas`) | 1 | 1 | 17 | 0 | 0 | 0.86 | 7.80 |
| Bree (`bree`) | 3 | 3 | 16 | 0 | 0 | 0.81 | 11.70 |
| Minas Tirith: Crypts (`gondorcrypts`) | 229.5 | 45 | 16 | 0 | 0 | 0.81 | 0.00 |
| Kallrist, Inner (`kallristinner`) | 6 | 5 | 15 | 0 | 0 | 0.76 | 0.00 |
| The Dimrill Stair (`thedimrillstair`) | 7.5 | 6 | 10 | 1 | 0 | 0.67 | 0.00 |
| Lothlorien: North (`lothloriennorth`) | 102 | 35 | 13 | 0 | 0 | 0.66 | 0.00 |
| Path To Helm's Deep (`pathtohelmsdeep`) | 222 | 45 | 13 | 0 | 0 | 0.66 | 1.20 |
| The Ruins of Dale (`theruinsofdale`) | 1 | 1 | 9 | 1 | 0 | 0.62 | 1.80 |
| Cirith Ungol (`cirithungol`) | 195.5 | 44 | 12 | 0 | 0 | 0.61 | 4.50 |
| Kallrist, West shore (`kallristeastshor`) | 6 | 5 | 12 | 0 | 0 | 0.61 | 0.00 |
| Old North Road (`greenwaynorth`) | 3 | 3 | 11 | 0 | 0 | 0.56 | 3.00 |
| The Stinkin Sewer (`thestinkinsewer`) | 2 | 2 | 11 | 0 | 0 | 0.56 | 23.70 |
| House of Nazgûl (`nazgulguildhouse`) | 48 | 30 | 7 | 1 | 0 | 0.52 | 1.20 |
| Mount Doom: Upper Level (`mountdoom`) | 40 | 30 | 10 | 0 | 0 | 0.51 | 12.60 |
| Northern Forests of Ithilien (NW) (`northernforestso`) | 202 | 45 | 10 | 0 | 0 | 0.51 | 0.00 |
| Northern Harad (`harad`) | 179.5 | 43 | 10 | 0 | 0 | 0.51 | 0.00 |
| Númenor:  Bay of Andúnië (`heavensscorn`) | 1028 | 55 | 10 | 0 | 0 | 0.51 | 0.00 |
| Road to Barad-Dûr (`roadtobaraddur`) | 3 | 3 | 10 | 0 | 0 | 0.51 | 0.00 |
| Sharkey's Mill (`sharkeysmill`) | 1 | 1 | 10 | 0 | 0 | 0.51 | 0.00 |
| Bill Ferny's House (`billfernyshouse`) | 2 | 2 | 9 | 0 | 0 | 0.45 | 1.20 |
| Gwathdor:  East Deeps (`gwathdordeeps`) | 238 | 45 | 9 | 0 | 0 | 0.45 | 0.00 |
| Kallrist, Outer banks (`kallristouterban`) | 17 | 13 | 9 | 0 | 0 | 0.45 | 0.00 |
| Mirkwood: Crypt Lower (`area002`) | 445 | 48 | 9 | 0 | 0 | 0.45 | 0.00 |
| Northern Forests of Ithilien (N) (`northernfores001`) | 214 | 45 | 9 | 0 | 0 | 0.45 | 0.00 |
| Northern Forests of Ithilien (S) (`northernfores004`) | 190 | 44 | 9 | 0 | 0 | 0.45 | 0.00 |
| Northern Forests of Ithilien (SW) (`northernfores005`) | 190 | 44 | 9 | 0 | 0 | 0.45 | 0.00 |
| Old Forest (`alterwald`) | 21 | 16 | 9 | 0 | 0 | 0.45 | 0.00 |
| Old Forest (`oldforest001`) | 39 | 29 | 9 | 0 | 0 | 0.45 | 0.00 |
| The Cirith Ungol Pass (`thecirithungolpa`) | 171 | 42 | 9 | 0 | 0 | 0.45 | 4.50 |
| The Gates of Moria (`thegatesofmoria`) | 7 | 6 | 9 | 0 | 0 | 0.45 | 0.00 |
| Enchanted Caverns (`enchantedcave002`) | 15 | 11 | 5 | 1 | 0 | 0.42 | 2.80 |
| Gwathdor:  Labyrinth  (`area025`) | 238 | 45 | 8 | 0 | 0 | 0.40 | 0.00 |
| Gwathdor:  Outskirts (`gwathdoroutskirt`) | 171 | 42 | 7 | 0 | 0 | 0.35 | 0.00 |
| Mirkwood: Forest of Greenleaves (`woodoflegolas`) | 107 | 36 | 7 | 0 | 0 | 0.35 | 0.00 |
| Gwathdor:  Cave (`gwathdorcave`) | 61 | 31 | 6 | 0 | 0 | 0.30 | 0.00 |
| Dimholt: Dunharrow (`dunharrow`) | 64 | 32 | 5 | 0 | 0 | 0.25 | 0.00 |
| Henneth Annun (`hennethannun002`) | 225 | 45 | 5 | 0 | 0 | 0.25 | 0.00 |
| Old Forest:  Withywindle Path (`area012`) | 1 | 1 | 5 | 0 | 0 | 0.25 | 0.00 |
| Vale of Henneth Annun (`hennethannun`) | 190 | 44 | 5 | 0 | 0 | 0.25 | 0.00 |
| Dol Guldur:  Tower Of Black Magic Main Hall (`dolguldurcastle`) | 514 | 48 | 4 | 0 | 0 | 0.20 | 0.00 |
| Mount Doom: Grand Hall (`area014`) | 946.5 | 54 | 4 | 0 | 0 | 0.20 | 16.80 |
| Old Road (`oldbackroad`) | 21 | 16 | 4 | 0 | 0 | 0.20 | 0.00 |
| Tower of the High Wizard: Ground Floor (`area011`) | 136 | 39 | 4 | 0 | 0 | 0.20 | 0.00 |
| Dol Guldur (`dolguldur001`) | 67 | 32 | 3 | 0 | 0 | 0.15 | 0.00 |
| Emyn Arnen: Top (`gondoremynarnen`) | 20 | 15 | 3 | 0 | 0 | 0.15 | 0.00 |
| Fangorn Forest (`fangornforest`) | 43 | 30 | 3 | 0 | 0 | 0.15 | 0.00 |
| Carn Dum: Smithy (`carndumsmithy`) | 35 | 26 | 2 | 0 | 0 | 0.10 | 0.00 |
| Bag End (`bagend001`) | 424 | 47 | 1 | 0 | 0 | 0.05 | 5.40 |
| Bilbo's House (`shirebilbohouse`) | 424 | 47 | 1 | 0 | 0 | 0.05 | 0.00 |
| Fangorn: Outskirts (`fangornoutskirts`) | 43 | 30 | 1 | 0 | 0 | 0.05 | 0.00 |

