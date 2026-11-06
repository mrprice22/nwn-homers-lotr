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
`loot/levels.json` `cr_points`: CR 10 = 8, CR 25 = 19, CR 55 = 31, CR 100 = 35, CR 250 = 45, CR 500 = 48, CR 1000 = 55. An area's loot level is the 75th-percentile CR of
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
| 3 | 348 | 8.4% | 77 | 60 |
| **5** | 203 | 4.9% | 49 | 44 |
| 7 | 123 | 3.0% | 33 | 34 |
| 10 | 55 | 1.3% | 20 | 22 |
| 15 | 34 | 0.8% | 16 | 15 |

## Totals at margin 5

| class | slots | distinct creatures | drops per full clear |
|---|---|---|---|
| normal | 3931 | 427 | 157.2 |
| elite | 203 | 49 | 50.8 |
| boss | 80 | 80 | 184.0 |
| excluded | 0 | 0 | 0 |

Rarity mix of one roll: normal: Common 56.4% / Uncommon 29.2% / Rare 10.8% / Epic 3.0% / Legendary 0.6%; boss: Epic 97.5% / Legendary 2.5% (elite rolls like normal).

## Elite creatures at margin 5

Grouped by area. *over* = how far the creature's loot level is above the area's.

| area | area CR | area lvl | creature | resref | CR | loot lvl | over | slots | why |
|---|---|---|---|---|---|---|---|---|---|
| Angmar (`angmar`) | 20 | 15 | Tirg the General | `gntfire001` | 53 | 31 | +16 | 1 | auto |
| Dunland (`dunland`) | 9 | 7 | Dunland Shaman | `uthgard006` | 80 | 33 | +26 | 1 | auto |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 12 | 9 | Wilder Chieftain | `bugbearboss006` | 30 | 22 | +13 | 1 | auto |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 12 | 9 | Trollog Devestator | `ogremageboss001` | 21 | 16 | +7 | 3 | auto |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 11.5 | 9 | Darcara the Cruel | `darcarathecruel` | 26 | 19 | +10 | 1 | auto |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 11.5 | 9 | Trollog Devestator | `ogremageboss001` | 21 | 16 | +7 | 4 | auto |
| Edoras (`edoras`) | 80.75 | 33 | Elite Rohirrim Soldier | `arohirrimsold004` | 158 | 41 | +8 | 2 | auto |
| Enchanted Caverns (`enchantedcave002`) | 20 | 15 | Xanith The Mad | `xaniththemad004` | 32 | 24 | +9 | 1 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 12 | 9 | zep_dracolich | `zep_dracolich` | 42 | 30 | +21 | 1 | auto |
| Esgaroth Crypts (`cryptsofthelosts`) | 12 | 9 | (missing blueprint) | `nw_lich001` | 28 | 21 | +12 | 1 | auto |
| Gap of Rohan (`gapofrohaneast`) | 33 | 24 | A Ridermark Guardian | `arohirrimsold005` | 55 | 31 | +7 | 2 | auto |
| Gap of Rohan (`gapofrohaneast`) | 33 | 24 | A Rohirrim Soldier | `arohirrimsold001` | 42 | 30 | +6 | 2 | auto |
| Goblin Gate: Greater (`goblingategreate`) | 5 | 4 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +5 | 2 | auto |
| Goblin Gate: Lesser (`goblingatelesser`) | 5 | 4 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +5 | 1 | auto |
| Goblin Gate: Mines (`goblingatemines`) | 5 | 4 | Goblin Gate Warrior | `bugbearboss001` | 12 | 9 | +5 | 5 | auto |
| Goblin Town: Main Hall (`goblintownmainha`) | 8 | 6 | The Goblin King | `bugbearboss004` | 58 | 31 | +25 | 1 | auto |
| Goblin Town: Warrens (`goblintownwarren`) | 8 | 6 | Bobo | `goblinb001` | 463 | 48 | +42 | 5 | auto |
| Great East Road (`greateastroadb`) | 7 | 6 | (missing blueprint) | `nw_lich001` | 28 | 21 | +15 | 1 | auto |
| Great East Road (`greateastroadb`) | 7 | 6 | (missing blueprint) | `nw_lich003` | 17 | 13 | +7 | 1 | auto |
| Great East Road (`greateastroadb`) | 7 | 6 | (missing blueprint) | `nw_vampire003` | 16 | 12 | +6 | 1 | auto |
| Great East Road (`greateastroadc`) | 6 | 5 | (missing blueprint) | `nw_humanmerc006` | 15 | 11 | +6 | 1 | auto |
| Great East Road (`greateastroadc`) | 6 | 5 | (missing blueprint) | `nw_elfmerc006` | 14 | 11 | +6 | 1 | auto |
| Great East Road (`greateastroadc`) | 6 | 5 | (missing blueprint) | `nw_dwarfmerc006` | 13 | 10 | +5 | 1 | auto |
| Great East Road (`greateastroadc`) | 6 | 5 | (missing blueprint) | `nw_halfmerc006` | 13 | 10 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | (missing blueprint) | `nw_lich001` | 28 | 21 | +15 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | (missing blueprint) | `nw_lich003` | 17 | 13 | +7 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | (missing blueprint) | `nw_vampire003` | 16 | 12 | +6 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | (missing blueprint) | `nw_humanmerc006` | 15 | 11 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | (missing blueprint) | `nw_slaaddeth` | 15 | 11 | +5 | 1 | auto |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | (missing blueprint) | `nw_elfmerc006` | 14 | 11 | +5 | 1 | auto |
| House of Nazgûl (`nazgulguildhouse`) | 48 | 30 | Mashano, Messenger To The Witch King | `creature020` | 236 | 45 | +15 | 1 | auto |
| Kallrist Crypt (`kallristcryptlow`) | 13 | 10 | (missing blueprint) | `nw_lich001` | 28 | 21 | +11 | 4 | auto |
| Kallrist Crypt (`kallristcryptupp`) | 16 | 12 | (missing blueprint) | `nw_lich001` | 28 | 21 | +9 | 7 | auto |
| Kallrist Crypt (`kallristcryptupp`) | 16 | 12 | Burning Skeleton | `kallristundead` | 26 | 19 | +7 | 7 | auto |
| Loogaz Lair (`loogazlair`) | 3 | 3 | Loogaz | `humanoid_gobl001` | 13 | 10 | +7 | 1 | auto |
| Minas Tirith: Gates (`minastirithgates`) | 111.5 | 36 | Epic Gondorian Guardsman | `gondorianguar002` | 211 | 45 | +9 | 2 | auto |
| Minas Tirith: Gates (`minastirithgates`) | 111.5 | 36 | Gondorian Wizard | `gondorianwizard` | 200 | 45 | +9 | 1 | auto |
| Mindalf (`nindalf`) | 32.75 | 24 | Krenshar | `krenshar` | 41 | 30 | +6 | 3 | auto |
| Mirkwood: Central (`mirkwoodcentral`) | 21 | 16 | Lava Climber | `spidwra001` | 37 | 27 | +11 | 4 | auto |
| Mirkwood: Dol Guldur (`dolguldur`) | 264 | 45 | Dol Guldur Gate Keeper | `dolguldurgatek_2` | 701 | 51 | +6 | 1 | auto |
| Mirkwood: Dol Guldur (`dolguldur`) | 264 | 45 | Dol Guldur Gate Keeper | `dolguldurgatekee` | 696 | 51 | +6 | 1 | auto |
| Mirkwood: East (`mirkwoodeast`) | 21 | 16 | Lava Climber | `spidwra001` | 37 | 27 | +11 | 4 | auto |
| Mirkwood: West (`mirkwoodwest`) | 21 | 16 | Lava Climber | `spidwra001` | 37 | 27 | +11 | 5 | auto |
| Morannon - The Black Gate (`blackgatge`) | 136 | 39 | Gate Giant | `gategiant001_2` | 221 | 45 | +6 | 4 | auto |
| Morannon - The Black Gate (`blackgatge`) | 136 | 39 | Gate Shaman - Mordor Black Gate | `creature001_2` | 212 | 45 | +6 | 2 | auto |
| Moria Level 1 (Center) (`morialevel1cente`) | 12 | 9 | Trollog Devestator | `ogremageboss001` | 21 | 16 | +7 | 3 | auto |
| Plane of the Render (`planeoftherender`) | 18 | 14 | Raitheen the Watcher | `raitheen` | 60 | 31 | +17 | 1 | auto |
| Plane of the Render (`planeoftherender`) | 18 | 14 | Render the Mammoth Watcher | `grayrend001` | 40 | 30 | +16 | 1 | auto |
| Sharkey's Chamber (`sharkeyschamber`) | 4 | 3 | Smithey the Sneak | `halfmerc002` | 13 | 10 | +7 | 1 | auto |
| Temple of Nazgul (`area010`) | 126 | 38 | Nazgul | `thundergut` | 255 | 45 | +7 | 1 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 52 | 31 | Drider Militia | `drowfight021` | 650 | 50 | +19 | 2 | auto |
| The Angmar Mountain Range (`theangmarmountai`) | 52 | 31 | Black Numenorean Assassin | `numenoreanpatrol` | 331 | 46 | +15 | 2 | auto |
| The Barrow Downs (`thebarrowdowns`) | 6 | 5 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +5 | 9 | auto |
| The Dimrill Stair (`thedimrillstair`) | 8.75 | 7 | Sarumon's Personal Guard | `urukai` | 267 | 45 | +38 | 1 | auto |
| The Misty Mountains (`mistymountainsa`) | 10 | 8 | A Misty Mountains Giant | `mgiant` | 17 | 13 | +5 | 6 | auto |
| The Misty Mountains (`mistymountainsb`) | 10 | 8 | A Misty Mountains Giant | `mgiant` | 17 | 13 | +5 | 4 | auto |
| The Ruins of Dale (`theruinsofdale`) | 4 | 3 | Gerrey Halliams | `gerrey` | 17 | 13 | +10 | 1 | auto |
| The Secret Pass of Mordor (`thesecretpassofm`) | 6 | 5 | Mordor Orc Lieutenant Soldier | `urukai016` | 200 | 45 | +40 | 1 | auto |
| The Secret Pass of Mordor (`thesecretpassofm`) | 6 | 5 | Mordor Orc Warrior Soldier | `mordororcwarrior` | 50 | 30 | +25 | 1 | auto |
| The Secret Pass of Mordor (`thesecretpassofm`) | 6 | 5 | Mordor Orc Scout Soldier | `urukai_2` | 16 | 12 | +7 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 5.75 | 5 | (missing blueprint) | `nw_lich003` | 17 | 13 | +8 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 5.75 | 5 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +6 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 5.75 | 5 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +5 | 1 | auto |
| Tomb of Garmir (`tombofgarmir`) | 5.75 | 5 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +5 | 1 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 6 | 5 | (missing blueprint) | `nw_lich003` | 17 | 13 | +8 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 6 | 5 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +6 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 6 | 5 | Greater Servant of Sauron | `greatservanto001` | 13 | 10 | +5 | 5 | auto |
| Tomb of Mendegilath (`tombofmendegilat`) | 6 | 5 | (missing blueprint) | `nw_skeldevour` | 13 | 10 | +5 | 5 | auto |
| Tomb of Peran (`tombofperan`) | 8 | 6 | (missing blueprint) | `nw_lich003` | 17 | 13 | +7 | 4 | auto |
| Tomb of Peran (`tombofperan`) | 8 | 6 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +5 | 4 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 8 | 6 | (missing blueprint) | `nw_lich001` | 28 | 21 | +15 | 1 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 8 | 6 | Rukor the Summoner | `rukorthesummoner` | 28 | 21 | +15 | 1 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 8 | 6 | (missing blueprint) | `nw_lich003` | 17 | 13 | +7 | 9 | auto |
| Tomb of Vinyalonde (`tombofvinyalonde`) | 8 | 6 | (missing blueprint) | `nw_doomkghtboss` | 15 | 11 | +5 | 9 | auto |
| Wold North (`thewold`) | 20 | 15 | Krenshar | `krenshar` | 41 | 30 | +15 | 5 | auto |
| Wold North (`thewold`) | 20 | 15 | Malar Panther | `malarpanther` | 30 | 22 | +7 | 5 | auto |
| Wold South (`woldsouth`) | 20 | 15 | Krenshar | `krenshar` | 41 | 30 | +15 | 6 | auto |
| Wold South (`woldsouth`) | 20 | 15 | Malar Panther | `malarpanther` | 30 | 22 | +7 | 6 | auto |

## Drops per area

Areas with hostile creatures, by drops per clear (highest first).

| area | area CR | lvl | slots | elite | boss | drops per clear | chest gear per fill |
|---|---|---|---|---|---|---|---|
| Tomb of Vinyalonde (`tombofvinyalonde`) | 8 | 6 | 208 | 20 | 0 | 12.52 | 50.70 |
| Tomb of Mendegilath (`tombofmendegilat`) | 6 | 5 | 156 | 20 | 0 | 10.44 | 38.70 |
| Morannon - The Black Gate (`blackgatge`) | 136 | 39 | 34 | 6 | 2 | 6.74 | 0.00 |
| The Barrow Downs (`thebarrowdowns`) | 6 | 5 | 117 | 9 | 0 | 6.57 | 0.00 |
| Greenway (South) (`greenwaysouth`) | 7 | 6 | 130 | 6 | 0 | 6.46 | 1.20 |
| Weather Top's Hidden Court (`area028`) | 3325 | 56 | 2 | 0 | 2 | 6.20 | 0.00 |
| Wold South (`woldsouth`) | 20 | 15 | 90 | 12 | 0 | 6.12 | 8.10 |
| Kallrist Crypt (`kallristcryptupp`) | 16 | 12 | 66 | 14 | 0 | 5.58 | 0.60 |
| Minas Tirith: Gates (`minastirithgates`) | 111.5 | 36 | 20 | 3 | 2 | 5.55 | 0.00 |
| Tomb of Peran (`tombofperan`) | 8 | 6 | 94 | 8 | 0 | 5.44 | 24.00 |
| Dwarrow Delf (west) (`dwarrowdelfeast`) | 11.5 | 9 | 107 | 5 | 0 | 5.33 | 31.50 |
| Edoras (`edoras`) | 80.75 | 33 | 16 | 2 | 2 | 5.18 | 3.00 |
| Wold North (`thewold`) | 20 | 15 | 75 | 10 | 0 | 5.10 | 13.80 |
| Kallrist Crypt (`kallristcryptlow`) | 13 | 10 | 53 | 4 | 1 | 5.02 | 18.90 |
| Dol Guldur City (`dolguldurcity`) | 245 | 45 | 21 | 0 | 2 | 4.96 | 0.00 |
| Orc Armory (`orcarmory`) | 251 | 45 | 15 | 0 | 2 | 4.72 | 1.20 |
| Helm's Deep: Keep (`area008`) | 296 | 46 | 14 | 0 | 2 | 4.68 | 9.80 |
| Isengard (Innerrim) (`isengardinnerrim`) | 207 | 45 | 11 | 0 | 2 | 4.56 | 0.00 |
| The Halls of Truth (`halloftruth`) | 94 | 35 | 10 | 0 | 2 | 4.52 | 0.00 |
| Rivendell Upper Halls (`rivendellupperha`) | 629 | 50 | 6 | 0 | 2 | 4.36 | 0.00 |
| Minas Tirith: Watchman Defender's Head Quarters (`watchmandefender`) | 83.75 | 34 | 2 | 0 | 2 | 4.20 | 0.00 |
| Tower of Orthanc: Saruman's Chambers (`towerofothancsar`) | - | 0 | 2 | 0 | 2 | 4.20 | 0.00 |
| Minas Tirith: City (`minastirith`) | 200 | 45 | 25 | 0 | 1 | 4.06 | 0.00 |
| The Misty Mountains (`mistymountainsa`) | 10 | 8 | 63 | 6 | 0 | 3.78 | 6.30 |
| Goblin Gate: Mines (`goblingatemines`) | 5 | 4 | 64 | 5 | 0 | 3.61 | 28.20 |
| Dimholt: The Forgotten King (`forgottenking`) | 59.5 | 31 | 12 | 0 | 1 | 3.54 | 0.00 |
| Helm's Deep: Cave (`area013`) | 344 | 46 | 12 | 0 | 1 | 3.54 | 0.00 |
| Mount Doom: Halls of Sauron  (`area016`) | 410 | 47 | 12 | 0 | 1 | 3.54 | 0.00 |
| Minas Tirith: Keep (`area005`) | 288 | 46 | 9 | 0 | 1 | 3.42 | 3.60 |
| Númenor:  Noirinan (`falseheaven`) | 1028 | 55 | 9 | 0 | 1 | 3.42 | 3.00 |
| The Trollshaws (`thetrollshalls`) | 7 | 6 | 32 | 0 | 1 | 3.34 | 0.00 |
| Tomb of Garmir (`tombofgarmir`) | 5.75 | 5 | 62 | 4 | 0 | 3.32 | 4.80 |
| Lothlorien: Main (`lothlorien`) | 214 | 45 | 30 | 0 | 1 | 3.26 | 0.00 |
| Rhosgobel:  Tower (`rhosgobeltower`) | 658 | 50 | 5 | 0 | 1 | 3.26 | 0.00 |
| Gwathdor:  Throne of the Lord (`gwaththrone`) | 588.25 | 49 | 4 | 0 | 1 | 3.22 | 0.00 |
| Mount Gundabad (`mountgundabadlev`) | 51 | 31 | 29 | 0 | 1 | 3.22 | 33.60 |
| The Witch King's Throne (`thewitchkingsthr`) | 348.25 | 46 | 4 | 0 | 1 | 3.22 | 0.00 |
| Gollum's Chambers (`area007`) | 1029 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| Hobbiton (`shirehobbiton001`) | - | 3 | 1 | 0 | 1 | 3.10 | 3.60 |
| Mirkwoods - Halls of Greenleafs (`area023`) | 1418 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| The Ruins of Dale: Cavern (`darkcavern`) | 1048 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| Tower of the High Wizard: The High Wizard's Chamber (`towerofthehighwi`) | 1795 | 55 | 1 | 0 | 1 | 3.10 | 0.00 |
| Mirkwood: Dol Guldur (`dolguldur`) | 264 | 45 | 15 | 2 | 1 | 3.08 | 8.40 |
| Helm's Deep (`helmsdeep001`) | 240 | 45 | 22 | 0 | 1 | 2.94 | 0.00 |
| Bree Crypt (`breecrypt`) | 4 | 3 | 73 | 0 | 0 | 2.92 | 5.40 |
| Great East Road (`greateastroadc`) | 6 | 5 | 51 | 4 | 0 | 2.88 | 0.00 |
| Mirkwood: West (`mirkwoodwest`) | 21 | 16 | 45 | 5 | 0 | 2.85 | 0.00 |
| Goblin Town: Warrens (`goblintownwarren`) | 8 | 6 | 44 | 5 | 0 | 2.81 | 4.80 |
| Mirkwood: Central East (`mirkwoodcentrale`) | 45 | 30 | 16 | 0 | 1 | 2.70 | 0.00 |
| Great East Road (`greateastroadb`) | 7 | 6 | 50 | 3 | 0 | 2.63 | 0.00 |
| Isengard (Outerrim) (`isengardouterrim`) | 184 | 43 | 14 | 0 | 1 | 2.62 | 0.00 |
| The Valley of Rivendell (`thevalleyofriven`) | 215 | 45 | 14 | 0 | 1 | 2.62 | 0.00 |
| Lonely Mountain: Main Hall (`lonelymountainma`) | 55 | 31 | 13 | 0 | 1 | 2.58 | 0.00 |
| Shelob's Lair (`shelobslair`) | 168 | 42 | 13 | 0 | 1 | 2.58 | 7.20 |
| Carn Dum: City (`carndumcity`) | 50.25 | 30 | 12 | 0 | 1 | 2.54 | 0.00 |
| Caves of Dol Guldur (`cavesofdolguldur`) | 264 | 45 | 12 | 0 | 1 | 2.54 | 8.40 |
| Esgaroth Crypts (`cryptsofthelosts`) | 12 | 9 | 53 | 2 | 0 | 2.54 | 33.60 |
| Carn Dum: Temple (`carndumtemple`) | 51 | 31 | 10 | 0 | 1 | 2.46 | 0.00 |
| Beorn (`beorn`) | 65 | 32 | 9 | 0 | 1 | 2.42 | 0.00 |
| Rivendell (`rivendell`) | 215 | 45 | 9 | 0 | 1 | 2.42 | 0.00 |
| Carn Dum: Throne (`carndumthrone`) | 84 | 34 | 8 | 0 | 1 | 2.38 | 0.00 |
| Kerufall's Lair (`kerufallslair`) | 102 | 35 | 8 | 0 | 1 | 2.38 | 0.00 |
| Lothlorien: Flets (`lothlorienflets`) | 130 | 38 | 8 | 0 | 1 | 2.38 | 0.00 |
| Theoden's Hall (`theodenshall`) | 55 | 31 | 8 | 0 | 1 | 2.38 | 0.00 |
| Carn Dum (`carndum`) | 80 | 33 | 7 | 0 | 1 | 2.34 | 0.00 |
| Isengard (Magic Room) (`isengardmagicroo`) | 116 | 37 | 7 | 0 | 1 | 2.34 | 0.00 |
| Osgiliath: Citidal of the Stars (`citidelofstars`) | 190 | 44 | 7 | 0 | 1 | 2.34 | 0.00 |
| Temple of Marr (`thehallsoftruth`) | 94 | 35 | 7 | 0 | 1 | 2.34 | 0.00 |
| Mirkwood: Central (`mirkwoodcentral`) | 21 | 16 | 37 | 4 | 0 | 2.32 | 0.00 |
| Angmar's Lair (`area009`) | 646.75 | 50 | 6 | 0 | 1 | 2.30 | 0.00 |
| Emyn Arnen: Peak (`emynarnen`) | 20 | 15 | 6 | 0 | 1 | 2.30 | 0.00 |
| Tower of Orthanc (`toweroforthanc`) | 176.75 | 42 | 6 | 0 | 1 | 2.30 | 0.00 |
| Mirkwood: East (`mirkwoodeast`) | 21 | 16 | 36 | 4 | 0 | 2.28 | 0.00 |
| Kallrist, North shore (`kallristnorthsho`) | 18 | 14 | 56 | 0 | 0 | 2.24 | 0.00 |
| The Temple of Morannon (`thetempleofmoran`) | 7 | 6 | 4 | 0 | 1 | 2.22 | 0.00 |
| Loogaz Lair (`loogazlair`) | 3 | 3 | 50 | 1 | 0 | 2.21 | 20.40 |
| Dol Guldur:  Tower Of Black Magic Depths (`dolguldurcast001`) | 680.5 | 51 | 3 | 0 | 1 | 2.18 | 0.00 |
| Mirkwood: Thranduil's Hall (`thranduilshall`) | 316.5 | 46 | 3 | 0 | 1 | 2.18 | 7.50 |
| Tower of the High Wizard: The Library (`towerofthehig001`) | 250.5 | 45 | 3 | 0 | 1 | 2.18 | 0.00 |
| The Misty Mountains (`mistymountainsb`) | 10 | 8 | 32 | 4 | 0 | 2.12 | 1.20 |
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
| Plane of the Render (`planeoftherender`) | 18 | 14 | 38 | 2 | 0 | 1.94 | 0.00 |
| The Angmar Mountain Range (`theangmarmountai`) | 52 | 31 | 27 | 4 | 0 | 1.92 | 0.00 |
| Goblin Gate: Greater (`goblingategreate`) | 5 | 4 | 37 | 2 | 0 | 1.90 | 0.00 |
| Dwarrow Delf (east) (`dwarrowdelfea001`) | 12 | 9 | 25 | 4 | 0 | 1.84 | 0.00 |
| Gap of Rohan (`gapofrohaneast`) | 33 | 24 | 24 | 4 | 0 | 1.80 | 0.00 |
| Nîn-in-Eilph (`cardolan`) | 10 | 8 | 45 | 0 | 0 | 1.80 | 0.00 |
| Ettenmoors (`ettenmoors`) | 91 | 34 | 44 | 0 | 0 | 1.76 | 0.00 |
| The Secret Pass of Mordor (`thesecretpassofm`) | 6 | 5 | 27 | 3 | 0 | 1.71 | 0.00 |
| Goblin Gate: Lesser (`goblingatelesser`) | 5 | 4 | 35 | 1 | 0 | 1.61 | 31.80 |
| Goblin Town: Main Hall (`goblintownmainha`) | 8 | 6 | 35 | 1 | 0 | 1.61 | 32.10 |
| The North Downs (`thenorthdowns001`) | 3 | 3 | 40 | 0 | 0 | 1.60 | 0.00 |
| Moria Level 1 (Center) (`morialevel1cente`) | 12 | 9 | 24 | 3 | 0 | 1.59 | 16.80 |
| Midgewater Swamp (`midgewaterswamp`) | 3 | 3 | 37 | 0 | 0 | 1.48 | 7.20 |
| Chamber of Records Wlkwy (`chamberofrecords`) | 8 | 6 | 36 | 0 | 0 | 1.44 | 0.00 |
| Enchanted Caverns (`enchantedcave001`) | 14.5 | 11 | 36 | 0 | 0 | 1.44 | 0.00 |
| Ered Duath Road: A (`eredduathroada`) | 171 | 42 | 35 | 0 | 0 | 1.40 | 4.80 |
| Carrok: Greater (`carrokgreater`) | 16 | 12 | 33 | 0 | 0 | 1.32 | 33.60 |
| Bree Caverns (`breecaverns`) | 3 | 3 | 32 | 0 | 0 | 1.28 | 36.60 |
| Gwathdor:  West Deeps (`gwathwest`) | 262 | 45 | 31 | 0 | 0 | 1.24 | 4.20 |
| The Abyss of Moria (`theabyssofmoria`) | 69 | 32 | 29 | 0 | 0 | 1.16 | 0.00 |
| Angmar Dungeon (`angmardungeon`) | 650 | 50 | 28 | 0 | 0 | 1.12 | 16.80 |
| Great East Road (`greateastroadd`) | 331 | 46 | 28 | 0 | 0 | 1.12 | 0.00 |
| Mindalf (`nindalf`) | 32.75 | 24 | 12 | 3 | 0 | 1.11 | 0.00 |
| Dead Marshes (`deadmarshes`) | 179 | 43 | 27 | 0 | 0 | 1.08 | 0.00 |
| Kallrist, East shore (`kallristwestshor`) | 18 | 14 | 27 | 0 | 0 | 1.08 | 0.00 |
| Carrok (`carrok`) | 16 | 12 | 26 | 0 | 0 | 1.04 | 0.00 |
| Great East Road (`greateastroada`) | 4 | 3 | 26 | 0 | 0 | 1.04 | 0.00 |
| Fornost (West) (`area004`) | 6 | 5 | 25 | 0 | 0 | 1.00 | 0.00 |
| Mirkwood: Central South (`mirkwoodcentrals`) | 45 | 30 | 25 | 0 | 0 | 1.00 | 0.00 |
| Celeduin Banks (`celeduinbanks`) | 6.25 | 5 | 24 | 0 | 0 | 0.96 | 0.00 |
| Chetwood (`chetwood001`) | 4 | 3 | 24 | 0 | 0 | 0.96 | 0.00 |
| Dimholt: The Gate of the Dead (`area018`) | 64 | 32 | 24 | 0 | 0 | 0.96 | 0.00 |
| Kallrist, Land bridge (`kallristdarkrim`) | 18 | 14 | 24 | 0 | 0 | 0.96 | 0.00 |
| Mount Doom: Lower Caverns (`mountdoom002`) | 178 | 42 | 24 | 0 | 0 | 0.96 | 0.00 |
| Númenor:  Arnenelos (`heavensdisdain`) | 1028 | 55 | 23 | 0 | 0 | 0.92 | 0.00 |
| Ruins of Annuminas (`ruinsofannuminas`) | 32 | 24 | 23 | 0 | 0 | 0.92 | 12.00 |
| Sharkey's Chamber (`sharkeyschamber`) | 4 | 3 | 17 | 1 | 0 | 0.89 | 20.10 |
| Carrok: Lesser (`carroklesser`) | 16 | 12 | 21 | 0 | 0 | 0.84 | 16.80 |
| Emyn Muil (`emynmuil`) | 68 | 32 | 21 | 0 | 0 | 0.84 | 0.00 |
| Great North Road (`gondorwesta`) | 42 | 30 | 21 | 0 | 0 | 0.84 | 0.00 |
| Great North Road (`gondorwestb`) | 42 | 30 | 21 | 0 | 0 | 0.84 | 0.00 |
| The Pelennor Fields (`thepelennorfield`) | 42 | 30 | 21 | 0 | 0 | 0.84 | 0.00 |
| Dunland (`dunland`) | 9 | 7 | 15 | 1 | 0 | 0.81 | 0.00 |
| Bree Cave (`breecave`) | 0.33 | 1 | 20 | 0 | 0 | 0.80 | 31.20 |
| Bree Crypt Lower Level (`breecryptlowerle`) | 4 | 3 | 20 | 0 | 0 | 0.80 | 0.00 |
| Dunland War Party (`dunlandwarparty`) | 8.25 | 6 | 20 | 0 | 0 | 0.80 | 16.20 |
| Ice Queen: Lair (`icequeenlair`) | 24 | 18 | 20 | 0 | 0 | 0.80 | 0.00 |
| Mount Gundabad Level 2 (`mountgundabad001`) | 90 | 34 | 20 | 0 | 0 | 0.80 | 12.60 |
| Angmar (`angmar`) | 20 | 15 | 13 | 1 | 0 | 0.73 | 0.00 |
| Durin's Bridge (`durinsbridge`) | 8 | 6 | 18 | 0 | 0 | 0.72 | 0.00 |
| Old Forest Road (`oldforestroad`) | 10 | 8 | 18 | 0 | 0 | 0.72 | 0.00 |
| Greenway (SouthEast) (`greenwaysoutheas`) | 3 | 3 | 17 | 0 | 0 | 0.68 | 7.80 |
| Bree (`bree`) | 4 | 3 | 16 | 0 | 0 | 0.64 | 11.70 |
| Minas Tirith: Crypts (`gondorcrypts`) | 260 | 45 | 16 | 0 | 0 | 0.64 | 0.00 |
| The Dimrill Stair (`thedimrillstair`) | 8.75 | 7 | 10 | 1 | 0 | 0.61 | 0.00 |
| Kallrist, Inner (`kallristinner`) | 7 | 6 | 15 | 0 | 0 | 0.60 | 0.00 |
| Mirkwood: North (`mirkwoodnorth`) | 45 | 30 | 15 | 0 | 0 | 0.60 | 0.00 |
| The Ruins of Dale (`theruinsofdale`) | 4 | 3 | 9 | 1 | 0 | 0.57 | 1.80 |
| Great North Road (`greatnorthroad`) | 40.5 | 30 | 14 | 0 | 0 | 0.56 | 0.00 |
| Mering Stream (`meringstream`) | 40.5 | 30 | 14 | 0 | 0 | 0.56 | 0.00 |
| Lothlorien: North (`lothloriennorth`) | 130 | 38 | 13 | 0 | 0 | 0.52 | 0.00 |
| Path To Helm's Deep (`pathtohelmsdeep`) | 344 | 46 | 13 | 0 | 0 | 0.52 | 1.20 |
| House of Nazgûl (`nazgulguildhouse`) | 48 | 30 | 7 | 1 | 0 | 0.49 | 1.20 |
| Temple of Nazgul (`area010`) | 126 | 38 | 7 | 1 | 0 | 0.49 | 0.00 |
| Cirith Ungol (`cirithungol`) | 212.75 | 45 | 12 | 0 | 0 | 0.48 | 4.50 |
| Kallrist, West shore (`kallristeastshor`) | 7 | 6 | 12 | 0 | 0 | 0.48 | 0.00 |
| Old North Road (`greenwaynorth`) | 3 | 3 | 11 | 0 | 0 | 0.44 | 3.00 |
| The Stinkin Sewer (`thestinkinsewer`) | 2 | 2 | 11 | 0 | 0 | 0.44 | 23.70 |
| Enchanted Caverns (`enchantedcave002`) | 20 | 15 | 5 | 1 | 0 | 0.41 | 2.80 |
| Mount Doom: Upper Level (`mountdoom`) | 40 | 30 | 10 | 0 | 0 | 0.40 | 12.60 |
| Northern Forests of Ithilien (NW) (`northernforestso`) | 214 | 45 | 10 | 0 | 0 | 0.40 | 0.00 |
| Northern Harad (`harad`) | 315 | 46 | 10 | 0 | 0 | 0.40 | 0.00 |
| Númenor:  Bay of Andúnië (`heavensscorn`) | 1028 | 55 | 10 | 0 | 0 | 0.40 | 0.00 |
| Road to Barad-Dûr (`roadtobaraddur`) | 3.75 | 3 | 10 | 0 | 0 | 0.40 | 0.00 |
| Sharkey's Mill (`sharkeysmill`) | 3 | 3 | 10 | 0 | 0 | 0.40 | 0.00 |
| Bill Ferny's House (`billfernyshouse`) | 3 | 3 | 9 | 0 | 0 | 0.36 | 1.20 |
| Gwathdor:  East Deeps (`gwathdordeeps`) | 262 | 45 | 9 | 0 | 0 | 0.36 | 0.00 |
| Kallrist, Outer banks (`kallristouterban`) | 18 | 14 | 9 | 0 | 0 | 0.36 | 0.00 |
| Mirkwood: Crypt Lower (`area002`) | 445 | 48 | 9 | 0 | 0 | 0.36 | 0.00 |
| Northern Forests of Ithilien (N) (`northernfores001`) | 214 | 45 | 9 | 0 | 0 | 0.36 | 0.00 |
| Northern Forests of Ithilien (S) (`northernfores004`) | 214 | 45 | 9 | 0 | 0 | 0.36 | 0.00 |
| Northern Forests of Ithilien (SW) (`northernfores005`) | 214 | 45 | 9 | 0 | 0 | 0.36 | 0.00 |
| Old Forest (`alterwald`) | 21 | 16 | 9 | 0 | 0 | 0.36 | 0.00 |
| Old Forest (`oldforest001`) | 39 | 29 | 9 | 0 | 0 | 0.36 | 0.00 |
| The Cirith Ungol Pass (`thecirithungolpa`) | 200 | 45 | 9 | 0 | 0 | 0.36 | 4.50 |
| The Gates of Moria (`thegatesofmoria`) | 8 | 6 | 9 | 0 | 0 | 0.36 | 0.00 |
| Gwathdor:  Labyrinth  (`area025`) | 262 | 45 | 8 | 0 | 0 | 0.32 | 0.00 |
| Gwathdor:  Outskirts (`gwathdoroutskirt`) | 171 | 42 | 7 | 0 | 0 | 0.28 | 0.00 |
| Mirkwood: Forest of Greenleaves (`woodoflegolas`) | 107 | 36 | 7 | 0 | 0 | 0.28 | 0.00 |
| Gwathdor:  Cave (`gwathdorcave`) | 68 | 32 | 6 | 0 | 0 | 0.24 | 0.00 |
| Dimholt: Dunharrow (`dunharrow`) | 64 | 32 | 5 | 0 | 0 | 0.20 | 0.00 |
| Henneth Annun (`hennethannun002`) | 225 | 45 | 5 | 0 | 0 | 0.20 | 0.00 |
| Old Forest:  Withywindle Path (`area012`) | 1 | 1 | 5 | 0 | 0 | 0.20 | 0.00 |
| Vale of Henneth Annun (`hennethannun`) | 190 | 44 | 5 | 0 | 0 | 0.20 | 0.00 |
| Dol Guldur:  Tower Of Black Magic Main Hall (`dolguldurcastle`) | 551 | 49 | 4 | 0 | 0 | 0.16 | 0.00 |
| Mount Doom: Grand Hall (`area014`) | 1697 | 55 | 4 | 0 | 0 | 0.16 | 16.80 |
| Old Road (`oldbackroad`) | 21 | 16 | 4 | 0 | 0 | 0.16 | 0.00 |
| Tower of the High Wizard: Ground Floor (`area011`) | 143 | 39 | 4 | 0 | 0 | 0.16 | 0.00 |
| Dol Guldur (`dolguldur001`) | 67 | 32 | 3 | 0 | 0 | 0.12 | 0.00 |
| Emyn Arnen: Top (`gondoremynarnen`) | 20 | 15 | 3 | 0 | 0 | 0.12 | 0.00 |
| Fangorn Forest (`fangornforest`) | 43 | 30 | 3 | 0 | 0 | 0.12 | 0.00 |
| Carn Dum: Smithy (`carndumsmithy`) | 35 | 26 | 2 | 0 | 0 | 0.08 | 0.00 |
| Bag End (`bagend001`) | 424 | 47 | 1 | 0 | 0 | 0.04 | 5.40 |
| Bilbo's House (`shirebilbohouse`) | 424 | 47 | 1 | 0 | 0 | 0.04 | 0.00 |
| Fangorn: Outskirts (`fangornoutskirts`) | 43 | 30 | 1 | 0 | 0 | 0.04 | 0.00 |

