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
| all with every item resolved | 828 | 367 (44%) | 512 | 675 (82%) | 742 |
| CRAdjust = 0 | 477 | 272 (57%) | 326 | 395 (83%) | 432 |
| CRAdjust != 0 | 351 | 95 (27%) | 186 | 280 (80%) | 310 |

2 blueprints have an item the formula cannot price (a hak-only item); they are left out.

## Summary of a full resync (every spawned non-utility blueprint off by more than 10%)

| | count |
|---|---|
| drifted blueprints that spawn | 82 |
| ... utility NPCs (`q_`, `cbd_`, `cp_`, `dmfi_`, `ds_`), CR probably hand-set on purpose | 1 |
| ... drift driven mostly by **item value** | 18 |
| ... other | 63 |
| CR would rise / fall | 30 / 52 |
| boss board: joins / leaves | 2 / 0 |
| area loot levels that change | 30 |
| loot-class changes (slots) | normal->elite 4, elite->normal 2 |

**Boss board changes:** joins `raitheen` (Raitheen the Watcher), `unnamedhorror` (Unnamed Horror); leaves none.

## Utility NPCs (likely hand-set - probably leave alone)

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| Combat Dummy | `cbd_dummy` | 1 | 444 | +44300% | hit_points | - | +0 | 1 | normal 1 -> normal 1 | `bree` |

## Drift driven by item value

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| Theoden's Chosen | `creature016` | 9540 | 6746 | -29% | items | `it_mneck002` 246,016,001 | +125 | 1 | boss 1 -> boss 1 | `area013` |
| Weathertop King | `weathertopkin004` | 3400 | 1878 | -45% | items | `thebladeofthe005` 54,243,974 | -120 | 1 | boss 1 -> boss 1 | `area028` |
| The Balrog of Moria | `azagoth001` | 555 | 1901 | +243% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `thebalrogofmoria` |
| Weathertop Queen | `weathertopque003` | 3100 | 1946 | -37% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area028` |
| Gloin King Under the Mountain | `adwarfguardia001` | 799 | 1437 | +80% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `lonelymountainma` |
| Barad Berserker | `baradberserker` | 246 | 864 | +251% | items | `bossring` 70,478,127 | +125 | 6 | - -> - |  |
| Elite Rohirrim Soldier | `arohirrimsold004` | 158 | 765 | +384% | items | `bossring` 70,478,127 | +1 | 2 | elite 1 -> elite 1 | `edoras` |
| Sauron's Chosen Minion | `sauronschosen005` | 551 | 1155 | +110% | items | `bossring` 70,478,127 | +125 | 4 | normal 2 -> normal 2 | `dolguldurcast001`, `dolguldurcastle` |
| Greater Black Numenorean Assassin | `numenoreanpat001` | 424 | 1026 | +142% | items | `bossring` 70,478,127 | +125 | 8 | normal 1 -> elite 1 | `angmardungeon` |
| Maggot Farmer | `maggotfarmer` | 436 | 1034 | +137% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `bywater` |
| Eowyn the Shieldmaiden | `eowyntheshieldma` | 693 | 1255 | +81% | items | `bossring` 70,478,127 | +76 | 1 | boss 1 -> boss 1 | `area008` |
| Gothmog Lord of Barad-Dur | `thehighmageofbar` | 604 | 1160 | +92% | items | `bossring` 70,478,127 | -125 | 1 | boss 1 -> boss 1 | `baraddurkeep` |
| Mount Doom Skeleton | `skeleton003` | 178 | 240 | +35% | items | `waxmbt005` 6,994,508 | +125 | 8 | normal 1 -> elite 1 | `mountdoom002` |
| Smithey the Sneak | `halfmerc002` | 13 | 50 | +285% | items | `scimitarofthequi` 7,302,390 | +0 | 1 | elite 1 -> elite 1 | `sharkeyschamber` |
| Galadriel | `galadriel` | 150 | 126 | -16% | items | `scimitaroflothor` 3,098,842 | +0 | 1 | boss 1 -> boss 1 | `lothlorien` |
| A Forgotten Soldier | `aforgottensoldio` | 58 | 65 | +12% | items | `dunharrowblade` 2,723,250 | -100 | 7 | normal 2 -> normal 2 | `area018`, `forgottenking` |
| Forgotten Warrior | `forgottenwarrior` | 64 | 71 | +11% | items | `dunharrowkama` 4,190,704 | -125 | 15 | normal 3 -> normal 3 | `area018`, `dunharrow`, `forgottenking` |
| Frust Ice Stone | `gntfrost010` | 24 | 30 | +25% | items | `wdbmsw007` 750,980 | +0 | 1 | normal 1 -> elite 1 | `icequeenlair` |

## Other drift (stats, levels, HP changed since the last toolset save)

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| <c¥  >»[The]«</c> <c¥  >»[Forger]«</c> | `methonashforge` | 17427 | 86 | -100% | saves | `` 0 | +0 | 1 | - -> - |  |
| <c¥  >»[The]«</c> <c¥  >»[Well-Mart]«</c> | `methonashmart` | 17427 | 86 | -100% | saves | `` 0 | +0 | 1 | - -> - |  |
| High Wizard of Gondor | `highwizardofgo_2` | 1795 | 604 | -66% | hit_points | `` 0 | +125 | 1 | boss 1 -> boss 1 | `towerofthehighwi` |
| Temple Mistress | `templemistress_2` | 980 | 241 | -75% | hit_points | `` 0 | +0 | 1 | boss 1 -> boss 1 | `blackgatge` |
| Radagast the Brown | `radagastthebro_2` | 1086 | 625 | -42% | hit_points | `` 0 | +124 | 1 | boss 1 -> boss 1 | `rhosgobeltower` |
| The Rancid Skinner Green Mortal of Khamul | `creature023_2` | 810 | 478 | -41% | hit_points | `` 0 | +122 | 1 | boss 1 -> boss 1 | `dolguldurcast001` |
| Fell Beast | `badass_2` | 333 | 75 | -77% | abilities | `` 0 | +0 | 1 | boss 1 -> boss 1 | `kallristcryptlow` |
| Elrond | `elrond001_2` | 829 | 590 | -29% | hit_points | `` 0 | +125 | 1 | boss 1 -> boss 1 | `rivendellupperha` |
| Ulmo the Valar | `ulmothevalar_2` | 650 | 442 | -32% | hit_points | `` 0 | +0 | 1 | boss 1 -> boss 1 | `area022` |
| High Priest of Gondor | `shopkeep002_2` | 447 | 243 | -46% | hit_points | `` 0 | +50 | 1 | boss 1 -> boss 1 | `minastirithtemp` |
| Gimli | `gimli_2` | 418 | 226 | -46% | hit_points | `` 0 | +125 | 1 | boss 1 -> boss 1 | `halloftruth` |
| Shadow Lord of Dol Guldur | `shadowlordof_2` | 660 | 494 | -25% | hit_points | `` 0 | +124 | 1 | boss 1 -> boss 1 | `dolguldur` |
| Morgrond Captian of Dol Guldur | `akhorahil006_2` | 433 | 288 | -33% | hit_points | `` 0 | +124 | 1 | boss 1 -> boss 1 | `dolguldurcity` |
| Gate Giant | `gategiant001_2` | 221 | 92 | -58% | hit_points | `` 0 | +0 | 4 | elite 1 -> normal 1 | `blackgatge` |
| Laxus The Ship Captain | `gandalfthegrey_2` | 198 | 76 | -62% | hit_points | `` 0 | -16 | 1 | - -> - |  |
| Laxus The Ship Captain | `gandalfthegrey_3` | 198 | 76 | -62% | hit_points | `` 0 | -16 | 1 | - -> - |  |
| Thranduil, King of Eryn Lasgalen | `thranduil_2` | 476 | 354 | -26% | hit_points | `` 0 | +0 | 1 | boss 1 -> boss 1 | `thranduilshall` |
| Bilbo Baggins | `bilbobaggins` | 424 | 536 | +26% | hit_points | `bilbosdefense` 11,467,197 | +26 | 2 | normal 2 -> normal 2 | `bagend001`, `shirebilbohouse` |
| Dol Guldur Gate Keeper | `dolguldurgatek_2` | 701 | 600 | -14% | hit_points | `` 0 | +125 | 1 | elite 1 -> elite 1 | `dolguldur` |
| Éothain Captian of Helm's Deep | `creature017_2` | 440 | 340 | -23% | hit_points | `` 0 | +5 | 1 | boss 1 -> boss 1 | `helmsdeep001` |
| Sauron's Personal Gaurds | `guardsofconsta_2` | 410 | 315 | -23% | hit_points | `` 0 | +125 | 7 | normal 1 -> normal 1 | `area016` |
| Deekin the General | `bauglirthegene_2` | 336 | 256 | -24% | hit_points | `` 0 | -15 | 1 | boss 1 -> boss 1 | `orcarmory` |
| Nature's Defender | `forestwalkerof_2` | 157 | 96 | -39% | hit_points | `` 0 | +0 | 2 | normal 1 -> normal 1 | `thranduilshall` |
| Anaralia, The widow maker | `anaraliathewidow` | 248 | 293 | +18% | hit_points | `lesserrobe3or004` 9,830,723 | +0 | 1 | boss 1 -> boss 1 | `mirkwoodcentrale` |
| Numarok The Black Hand | `cultmember002_2` | 130 | 85 | -35% | hit_points | `` 0 | -29 | 1 | boss 1 -> boss 1 | `area078` |
| Numanan Numerocks Second Hand | `cultmember002_3` | 130 | 85 | -35% | hit_points | `` 0 | -29 | 1 | boss 1 -> boss 1 | `carndumcity` |
| A Dwarf Ajudicator | `adwarfajudica0_2` | 94 | 52 | -45% | hit_points | `` 0 | +0 | 8 | normal 3 -> normal 3 | `halloftruth`, `lonelymountainma`, `thehallsoftruth` |
| Gate Axeman | `gateaxeman_2` | 136 | 99 | -27% | hit_points | `` 0 | +0 | 11 | normal 1 -> normal 1 | `blackgatge` |
| Raitheen the Watcher | `raitheen` | 60 | 97 | +62% | hit_points | - | +17 | 1 | elite 1 -> elite 1 | `planeoftherender` |
| Greater Elven Watcher | `greaterelvenw0_2` | 130 | 94 | -28% | hit_points | `` 0 | +28 | 6 | normal 2 -> normal 2 | `lothlorienflets`, `lothloriennorth` |
| Rail the White Hand Blaster | `railthewhiteh001` | 146 | 181 | +24% | hit_points | `staffoftheorcsha` 4,046,544 | +6 | 1 | boss 1 -> boss 1 | `isengardinnerrim` |
| Fail the White Hand Blaster | `railthewhiteh003` | 96 | 131 | +36% | hit_points | `staffoftheorcsha` 4,046,544 | +0 | 1 | boss 1 -> boss 1 | `isengardmagicroo` |
| Card Mennard | `arohirrimsold006` | 201 | 167 | -17% | hit_points | `rohirrimlongswor` 2,178,030 | +9 | 1 | boss 1 -> boss 1 | `edoras` |
| Dol - Guldur Smithy | `dolguldursmi` | 168 | 134 | -20% | hit_points | `` 0 | +93 | 1 | - -> - |  |
| Eowyn's Personal Guard | `helmsdeepguar0_2` | 250 | 217 | -13% | hit_points | `` 0 | +100 | 5 | normal 1 -> normal 1 | `area008` |
| Gate Shaman - Mordor Black Gate | `creature001_2` | 212 | 182 | -14% | hit_points | `` 0 | +123 | 2 | elite 1 -> elite 1 | `blackgatge` |
| Bowman of The Deep | `bowmanofthede001` | 145 | 169 | +17% | hit_points | `054` 1,325,390 | +39 | 9 | normal 1 -> normal 1 | `helmsdeep001` |
| Nazgûl Watcher | `creature004_2` | 48 | 27 | -44% | hit_points | `` 0 | +0 | 6 | normal 1 -> normal 1 | `nazgulguildhouse` |
| Black Numenorean Militia | `numenoreanmili_3` | 50 | 36 | -28% | abilities | `` 0 | +17 | 7 | normal 2 -> normal 2 | `mountgundabad001`, `mountgundabadlev` |
| Beorning (Shifted) | `bearbeorning001` | 65 | 56 | -14% | hit_points | `cloakoflothlorie` 129,960 | +0 | 3 | normal 1 -> normal 1 | `beorn` |
| Gondorian Bowman | `gondorianguar0_4` | 85 | 76 | -11% | hit_points | `` 0 | +27 | 1 | boss 1 -> boss 1 | `watchmandefender` |
| Uruk Hai White Hand's Chosen | `urukai008_2` | 50 | 41 | -18% | hit_points | `` 0 | +8 | 1 | normal 1 -> normal 1 | `toweroforthanc` |
| Beorning | `beorning001` | 53 | 45 | -15% | hit_points | `cloakoflothlorie` 129,960 | +0 | 5 | normal 1 -> normal 1 | `beorn` |
| Gwathdor Wizard | `gwathsorcerer` | 78 | 86 | +10% | saves | `gwatwizrobe` 1,053,815 | +0 | 5 | normal 1 -> normal 1 | `gwathwest` |
| Zombie of Dol Guldur | `zombieofdolguldu` | 75 | 83 | +11% | hit_points | `zombieflesh` 344,888 | +0 | 1 | normal 1 -> normal 1 | `dolguldur` |
| Black Numenorean Priestess | `drowcler024_2` | 46 | 39 | -15% | hit_points | `` 0 | +0 | 2 | normal 1 -> normal 1 | `carndumtemple` |
| Black Numenorean Priestess | `drowcler024_3` | 46 | 39 | -15% | hit_points | `` 0 | +0 | 7 | normal 2 -> normal 2 | `mountgundabad001`, `mountgundabadlev` |
| Unnamed Horror | `unnamedhorror` | 54 | 61 | +13% | hit_points | `undeadheart` 3,840,901 | -125 | 1 | normal 1 -> normal 1 | `area018` |
| White Widow | `spidgiant002` | 39 | 45 | +15% | abilities | - | +0 | 9 | normal 1 -> normal 1 | `oldforest001` |
| Thing of the Dark | `thingofthedark` | 40 | 46 | +15% | hit_points | `shadowdecayer` 3,821,130 | -125 | 8 | normal 2 -> normal 2 | `area018`, `forgottenking` |
| Appearance Lizard | `appearancelizard` | 33 | 38 | +15% | hit_points | - | +0 | 1 | - -> - |  |
| Black Numenorean Militia | `numenoreanmili_2` | 35 | 30 | -14% | abilities | `` 0 | +11 | 16 | normal 5 -> normal 5 | `carndum`, `carndumcity`, `carndumsmithy`, `carndumtemple` ... |
| Spider-Queen | `spiderboss001` | 27 | 32 | +19% | abilities | - | -17 | 24 | elite 3/normal 3 -> elite 3/normal 3 | `mirkwoodcentral`, `mirkwoodcentrale`, `mirkwoodcentrals`, `mirkwoodeast` ... |
| Dunland Shaman | `uthgard006_2` | 48 | 43 | -10% | hit_points | `` 0 | -15 | 1 | normal 1 -> normal 1 | `toweroforthanc` |
| Lesser Barrow Wight | `lesserbarrowwigh` | 6 | 3 | -50% | hit_points | `sauronsservantsw` 2,030 | -1 | 44 | normal 5 -> normal 5 | `thebarrowdowns`, `tombofgarmir`, `tombofmendegilat`, `tombofperan` ... |
| Keeper of The Peace | `luskanite002_2` | 16 | 13 | -19% | hd | `` 0 | +0 | 1 | - -> - |  |
| Goruz The Defiler | `bugwizb003` | 8 | 7 | -12% | hit_points | `nw_wblmcl010` 7,220 | +0 | 1 | normal 1 -> normal 1 | `goblintownmainha` |
| Dryad | `nymph001` | 3 | 2 | -33% | hit_points | - | +0 | 1 | - -> - |  |
| Trollog Channeler | `ogremage003` | 8 | 7 | -12% | hit_points | `nw_wswmgs002` 1,718 | +0 | 24 | normal 7 -> normal 7 | `chamberofrecords`, `durinsbridge`, `dwarrowdelfea001`, `dwarrowdelfeast` ... |
| Moria Orc Shaman | `orcwizb001` | 7 | 6 | -14% | hit_points | `nw_wdbqs001` 2 | +0 | 24 | normal 7 -> normal 7 | `chamberofrecords`, `durinsbridge`, `dwarrowdelfea001`, `dwarrowdelfeast` ... |
| Dunland Savage | `uthgard002` | 3 | 2 | -33% | hit_points | `nw_waxgr001` 40 | +1 | 8 | normal 2 -> normal 2 | `dunland`, `dunlandwarparty` |
| New Player's Guide | `npguide` | 0.25 | 1 | +75% | hit_points | - | +0 | 1 | - -> - |  |
| Barliman Butterbur | `merit_keeper` | 0.25 | 0.5 | +25% | hit_points | - | +0 | 2 | - -> - |  |

## Area loot levels after a full resync

| area | level now | after | chests |
|---|---|---|---|
| Angmar Dungeon (`angmardungeon`) | 48 | 50 | 8 |
| Mirkwood: Thranduil's Hall (`thranduilshall`) | 40 | 35 | 7 |
| Bag End (`bagend001`) | 47 | 49 | 4 |
| Carn Dum: Numerok's Den (`area078`) | 38 | 34 | 2 |
| House of Nazgûl (`nazgulguildhouse`) | 30 | 20 | 1 |
| Mount Doom: Halls of Sauron  (`area016`) | 47 | 46 | 0 |
| Dimholt: The Gate of the Dead (`area018`) | 31 | 32 | 0 |
| Valinor: Realm of the spirits (`area022`) | 50 | 48 | 0 |
| Weather Top's Hidden Court (`area028`) | 56 | 55 | 0 |
| Beorn (`beorn`) | 31 | 30 | 0 |
| Morannon - The Black Gate (`blackgatge`) | 39 | 38 | 0 |
| Carn Dum (`carndum`) | 26 | 22 | 0 |
| Carn Dum: City (`carndumcity`) | 28 | 26 | 0 |
| Carn Dum: Smithy (`carndumsmithy`) | 26 | 22 | 0 |
| Chamber of Records Wlkwy (`chamberofrecords`) | 6 | 5 | 0 |
| Dol Guldur:  Tower Of Black Magic Depths (`dolguldurcast001`) | 49 | 55 | 0 |
| Dol Guldur:  Tower Of Black Magic Main Hall (`dolguldurcastle`) | 48 | 52 | 0 |
| Durin's Bridge (`durinsbridge`) | 6 | 5 | 0 |
| The Halls of Truth (`halloftruth`) | 33 | 31 | 0 |
| Helm's Deep (`helmsdeep001`) | 39 | 42 | 0 |
| Minas Tirith: Temple (`minastirithtemp`) | 48 | 45 | 0 |
| Mirkwood: Central East (`mirkwoodcentrale`) | 22 | 24 | 0 |
| Mirkwood: Central South (`mirkwoodcentrals`) | 22 | 24 | 0 |
| Mirkwood: North (`mirkwoodnorth`) | 22 | 24 | 0 |
| Old Forest (`oldforest001`) | 29 | 30 | 0 |
| Bilbo's House (`shirebilbohouse`) | 47 | 49 | 0 |
| Moria: The Balrog of Moria (`thebalrogofmoria`) | 49 | 55 | 0 |
| The Dimrill Stair (`thedimrillstair`) | 6 | 5 | 0 |
| The Gates of Moria (`thegatesofmoria`) | 6 | 5 | 0 |
| Tower of the High Wizard: The High Wizard's Chamber (`towerofthehighwi`) | 55 | 50 | 0 |

