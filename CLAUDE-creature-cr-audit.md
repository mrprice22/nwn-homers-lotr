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
| all with every item resolved | 825 | 351 (43%) | 439 | 614 (74%) | 723 |
| CRAdjust = 0 | 475 | 267 (56%) | 302 | 374 (79%) | 424 |
| CRAdjust != 0 | 350 | 84 (24%) | 137 | 240 (69%) | 299 |

5 blueprints have an item the formula cannot price (a hak-only item); they are left out.

## Summary of a full resync (every spawned non-utility blueprint off by more than 10%)

| | count |
|---|---|
| drifted blueprints that spawn | 117 |
| ... utility NPCs (`q_`, `cbd_`, `cp_`, `dmfi_`, `ds_`), CR probably hand-set on purpose | 1 |
| ... drift driven mostly by **item value** | 39 |
| ... other | 77 |
| CR would rise / fall | 68 / 49 |
| boss board: joins / leaves | 2 / 0 |
| area loot levels that change | 40 |
| loot-class changes (slots) | normal->elite 4, elite->normal 3 |

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
| Theoden's Chosen | `creature016` | 9540 | 6965 | -27% | items | `it_mneck002` 246,016,001 | +125 | 1 | boss 1 -> boss 1 | `area013` |
| Legolas Greenleaf -  Silvan Prince of Mirkwood | `legolasgreenl001` | 1418 | 3310 | +133% | items | `bossring` 70,478,127 | +124 | 1 | boss 1 -> boss 1 | `area023` |
| The Balrog of Moria | `azagoth001` | 555 | 2273 | +310% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `thebalrogofmoria` |
| Weathertop King | `weathertopkin004` | 3400 | 2232 | -34% | items | `thebladeofthe005` 54,243,974 | -120 | 1 | boss 1 -> boss 1 | `area028` |
| Weathertop Queen | `weathertopque003` | 3100 | 2110 | -32% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area028` |
| Sauron's Chosen Minion | `sauronschosen005` | 551 | 1246 | +126% | items | `bossring` 70,478,127 | +125 | 4 | normal 2 -> normal 2 | `dolguldurcast001`, `dolguldurcastle` |
| Gloin King Under the Mountain | `adwarfguardia001` | 799 | 1493 | +87% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `lonelymountainma` |
| Barad Berserker | `baradberserker` | 246 | 916 | +272% | items | `bossring` 70,478,127 | +125 | 6 | - -> - |  |
| Khamûl The Ringwraith | `creature007` | 965 | 1607 | +67% | items | `shadowoftheeast` 4,524,350 | +123 | 1 | boss 1 -> boss 1 | `area031` |
| Greater Black Numenorean Assassin | `numenoreanpat001` | 424 | 1063 | +151% | items | `bossring` 70,478,127 | +125 | 8 | normal 1 -> normal 1 | `angmardungeon` |
| Eowyn the Shieldmaiden | `eowyntheshieldma` | 693 | 1327 | +91% | items | `bossring` 70,478,127 | +76 | 1 | boss 1 -> boss 1 | `area008` |
| Maggot Farmer | `maggotfarmer` | 436 | 1055 | +142% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `bywater` |
| Elite Rohirrim Soldier | `arohirrimsold004` | 158 | 765 | +384% | items | `bossring` 70,478,127 | +1 | 2 | elite 1 -> elite 1 | `edoras` |
| Gothmog Lord of Barad-Dur | `thehighmageofbar` | 604 | 1171 | +94% | items | `bossring` 70,478,127 | -125 | 1 | boss 1 -> boss 1 | `baraddurkeep` |
| Witch King Leader of The Nine | `witchking` | 1198 | 1561 | +30% | items | `bossring_ci` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `thewitchkingsthr` |
| Gwathdor Lord of the Dark Arts | `gwathdorlord001` | 1615 | 1893 | +17% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `gwaththrone` |
| Underlord of Sauron | `mummyboss001` | 1697 | 1894 | +12% | items | `mindmelter001` 49,651,898 | +125 | 2 | normal 1 -> normal 1 | `area014` |
| The Mighty Smaug | `themightysmag002` | 1048 | 1235 | +18% | items | `bossring` 70,478,127 | +123 | 1 | boss 1 -> boss 1 | `darkcavern` |
| Sauron The Abhorred | `creature019` | 1768 | 1949 | +10% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area016` |
| Denethor, Steward of Gondor | `creature003` | 1459 | 1617 | +11% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area005` |
| Angmar | `angmar` | 637 | 779 | +22% | items | `rapierofangmar` 17,158,820 | +125 | 1 | boss 1 -> boss 1 | `area009` |
| Drider Militia | `drowfight021` | 650 | 725 | +12% | items | `headsplitter004` 37,613,486 | +11 | 16 | elite 2/normal 2 -> elite 2/normal 2 | `angmardungeon`, `area009`, `greateastroadd`, `theangmarmountai` |
| Nazgul | `thundergut` | 255 | 330 | +29% | items | `item057` 4,133,708 | +95 | 1 | elite 1 -> elite 1 | `area010` |
| Gimli | `gimli_2` | 418 | 356 | -15% | items | `item044` 12,860,130 | +125 | 1 | boss 1 -> boss 1 | `halloftruth` |
| Mount Doom Skeleton | `skeleton003` | 178 | 240 | +35% | items | `waxmbt005` 6,994,508 | +125 | 8 | normal 1 -> elite 1 | `mountdoom002` |
| Bowman of The Deep | `bowmanofthede001` | 145 | 205 | +41% | items | `054` 1,325,390 | +39 | 9 | normal 1 -> normal 1 | `helmsdeep001` |
| Dol Guldur Orc General | `akhorahil004` | 277 | 326 | +18% | items | `127` 7,317,142 | +125 | 1 | boss 1 -> boss 1 | `dolguldurcity` |
| Fist of Sauron | `creature008` | 289 | 338 | +17% | items | `item020` 4,515,843 | +122 | 28 | - -> - |  |
| Smithey the Sneak | `halfmerc002` | 13 | 50 | +285% | items | `scimitarofthequi` 7,302,390 | +0 | 1 | elite 1 -> elite 1 | `sharkeyschamber` |
| Mirkwood Forest Walker | `mirkwoodforestwa` | 107 | 141 | +32% | items | `rapierofmirkwood` 2,155,000 | +0 | 7 | normal 1 -> normal 1 | `woodoflegolas` |
| Rohirrim Archer | `rohirrimbowme001` | 222 | 254 | +14% | items | `150` 3,332,176 | +125 | 11 | normal 2 -> normal 2 | `area013`, `pathtohelmsdeep` |
| Galadriel | `galadriel` | 150 | 127 | -15% | items | `scimitaroflothor` 3,098,842 | +0 | 1 | boss 1 -> boss 1 | `lothlorien` |
| Mordor Orc Bowman | `mordororcbowman` | 171 | 190 | +11% | items | `kukri051` 1,993,976 | +124 | 13 | normal 3 -> elite 1/normal 2 | `eredduathroada`, `orcarmory`, `thecirithungolpa` |
| Uruk Hai Bowman | `urukaibowman` | 92 | 110 | +20% | items | `urukhairapier` 766,400 | +13 | 8 | elite 1/normal 1 -> elite 1/normal 1 | `ettenmoors`, `isengardouterrim` |
| Mountain Giant | `mountaingiant` | 68 | 85 | +25% | items | `slingofgiants` 1,158,008 | +0 | 7 | normal 1 -> normal 1 | `emynmuil` |
| A Forgotten Soldier | `aforgottensoldio` | 58 | 65 | +12% | items | `dunharrowblade` 2,723,250 | -100 | 7 | normal 2 -> normal 2 | `area018`, `forgottenking` |
| Forgotten Warrior | `forgottenwarrior` | 64 | 71 | +11% | items | `dunharrowkama` 4,190,704 | -125 | 15 | normal 3 -> normal 3 | `area018`, `dunharrow`, `forgottenking` |
| Frust Ice Stone | `gntfrost010` | 24 | 31 | +29% | items | `wdbmsw007` 750,980 | +0 | 1 | normal 1 -> elite 1 | `icequeenlair` |
| Grokul Head Master | `minchief001` | 24 | 28 | +17% | items | `brainhew` 129,644 | +4 | 1 | elite 1 -> elite 1 | `planeoftherender` |

## Other drift (stats, levels, HP changed since the last toolset save)

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| <c¥  >»[The]«</c> <c¥  >»[Forger]«</c> | `methonashforge` | 17427 | 86 | -100% | saves | `` 0 | +0 | 1 | - -> - |  |
| <c¥  >»[The]«</c> <c¥  >»[Well-Mart]«</c> | `methonashmart` | 17427 | 86 | -100% | saves | `` 0 | +0 | 1 | - -> - |  |
| High Wizard of Gondor | `highwizardofgo_2` | 1795 | 732 | -59% | hit_points | `bastardofthehobb` 5,473,214 | +125 | 1 | boss 1 -> boss 1 | `towerofthehighwi` |
| Temple Mistress | `templemistress_2` | 980 | 243 | -75% | hit_points | `amuletofdirep002` 187,211 | +0 | 1 | boss 1 -> boss 1 | `blackgatge` |
| Khamûl The Ringwraith | `creature007_2` | 839 | 1390 | +66% | hit_points | `shadowoftheeast` 4,524,350 | +0 | 1 | boss 1 -> boss 1 | `carndumthrone` |
| Radagast the Brown | `radagastthebro_2` | 1086 | 791 | -27% | hit_points | `lesserrobe3or004` 9,830,723 | +124 | 1 | boss 1 -> boss 1 | `rhosgobeltower` |
| Fell Beast | `badass_2` | 333 | 75 | -77% | abilities | `` 0 | +0 | 1 | boss 1 -> boss 1 | `kallristcryptlow` |
| The Rancid Skinner Green Mortal of Khamul | `creature023_2` | 810 | 575 | -29% | hit_points | `wspmku011` 8,522,972 | +122 | 1 | boss 1 -> boss 1 | `dolguldurcast001` |
| High Priest of Gondor | `shopkeep002_2` | 447 | 245 | -45% | hit_points | `tearhuanch2` 100,702 | +50 | 1 | boss 1 -> boss 1 | `minastirithtemp` |
| Arwen, The Evenstar | `creature005` | 767 | 963 | +26% | hit_points | `item066` 11,026,204 | +125 | 1 | boss 1 -> boss 1 | `rivendellupperha` |
| High Priest of Morannon | `highpriestofmora` | 495 | 687 | +39% | hit_points | `maceofthedark001` 18,842,266 | +125 | 1 | boss 1 -> boss 1 | `thetempleofmoran` |
| Elrond | `elrond001_2` | 829 | 660 | -20% | hit_points | `celestialfury` 6,272,080 | +125 | 1 | boss 1 -> boss 1 | `rivendellupperha` |
| Frost | `frost001` | 256 | 417 | +63% | hit_points | `frostbite` 8,368,960 | -66 | 1 | boss 1 -> boss 1 | `emynarnen` |
| Gollum | `gollum` | 1029 | 1180 | +15% | hit_points | `item062` 6,756,840 | +0 | 1 | boss 1 -> boss 1 | `area007` |
| Morgrond Captian of Dol Guldur | `akhorahil006_2` | 433 | 288 | -33% | hit_points | `nw_it_mpotion012` 1,320 | +124 | 1 | boss 1 -> boss 1 | `dolguldurcity` |
| Mutated Basilisk | `basilisk007` | 417 | 551 | +32% | hit_points | `wplmsc005` 7,859,480 | +0 | 3 | normal 1 -> normal 1 | `area002` |
| Gate Giant | `gategiant001_2` | 221 | 92 | -58% | hit_points | `` 0 | +0 | 4 | elite 1 -> normal 1 | `blackgatge` |
| Kerufall | `kerufall003` | 418 | 546 | +31% | hit_points | `item031` 6,174,412 | +50 | 1 | boss 1 -> boss 1 | `kerufallslair` |
| Laxus The Ship Captain | `gandalfthegrey_2` | 198 | 76 | -62% | hit_points | `` 0 | -16 | 1 | - -> - |  |
| Laxus The Ship Captain | `gandalfthegrey_3` | 198 | 76 | -62% | hit_points | `` 0 | -16 | 1 | - -> - |  |
| Bilbo Baggins | `bilbobaggins` | 424 | 539 | +27% | hit_points | `bilbosdefense` 11,467,197 | +26 | 2 | normal 2 -> normal 2 | `bagend001`, `shirebilbohouse` |
| Éothain Captian of Helm's Deep | `creature017_2` | 440 | 340 | -23% | hit_points | `it_mpotion013` 2,640 | +5 | 1 | boss 1 -> boss 1 | `helmsdeep001` |
| Sauron's Personal Gaurds | `guardsofconsta_2` | 410 | 321 | -22% | hit_points | `x2_it_mring029` 357,012 | +125 | 7 | normal 1 -> normal 1 | `area016` |
| Dol Guldur Gate Keeper | `dolguldurgatek_2` | 701 | 621 | -11% | hit_points | `cloth027` 1,797,761 | +125 | 1 | elite 1 -> normal 1 | `dolguldur` |
| Deekin the General | `bauglirthegene_2` | 336 | 258 | -23% | hit_points | `x2_it_mneck022` 98,010 | -15 | 1 | boss 1 -> boss 1 | `orcarmory` |
| Shadow Lord of Dol Guldur | `shadowlordof_2` | 660 | 584 | -12% | hit_points | `item086` 9,112,580 | +124 | 1 | boss 1 -> boss 1 | `dolguldur` |
| Basilisk King | `basilisk008` | 564 | 637 | +13% | hit_points | `basilisktail006` 7,567,389 | +0 | 1 | boss 1 -> boss 1 | `area003` |
| Mutated Basilisk | `basilisk005` | 445 | 508 | +14% | hit_points | `ancientmace005` 7,365,954 | +0 | 3 | normal 1 -> normal 1 | `area002` |
| Nature's Defender | `forestwalkerof_2` | 157 | 96 | -39% | hit_points | `` 0 | +0 | 2 | normal 1 -> normal 1 | `thranduilshall` |
| Mutated Basilisk | `basilisk006` | 445 | 505 | +13% | hit_points | `ancientbow009` 7,197,150 | +0 | 3 | normal 1 -> normal 1 | `area002` |
| Archer of Dol Guldur | `archerofdolguldu` | 234 | 282 | +21% | hit_points | `wswmdg007` 3,018,648 | +1 | 10 | normal 2 -> normal 2 | `cavesofdolguldur`, `dolguldur` |
| Anaralia, The widow maker | `anaraliathewidow` | 248 | 295 | +19% | hit_points | `lesserrobe3or004` 9,830,723 | +0 | 1 | boss 1 -> boss 1 | `mirkwoodcentrale` |
| A Dwarf Ajudicator | `adwarfajudica0_2` | 94 | 52 | -45% | hit_points | `` 0 | +0 | 8 | normal 3 -> normal 3 | `halloftruth`, `lonelymountainma`, `thehallsoftruth` |
| Shelob | `shelob001` | 220 | 261 | +19% | hit_points | `legofshelob002` 890,422 | +124 | 1 | boss 1 -> boss 1 | `shelobslair` |
| Gate Axeman | `gateaxeman_2` | 136 | 99 | -27% | hit_points | `` 0 | +0 | 11 | normal 1 -> normal 1 | `blackgatge` |
| Raitheen the Watcher | `raitheen` | 60 | 97 | +62% | hit_points | - | +17 | 1 | elite 1 -> elite 1 | `planeoftherender` |
| Rail the White Hand Blaster | `railthewhiteh001` | 146 | 182 | +25% | hit_points | `staffoftheorcsha` 4,046,544 | +6 | 1 | boss 1 -> boss 1 | `isengardinnerrim` |
| Shadow Walker | `archerofdolgu001` | 264 | 299 | +13% | hit_points | `wswmdg007` 3,018,648 | +1 | 11 | normal 2 -> normal 2 | `cavesofdolguldur`, `dolguldur` |
| Fail the White Hand Blaster | `railthewhiteh003` | 96 | 131 | +36% | hit_points | `staffoftheorcsha` 4,046,544 | +0 | 1 | boss 1 -> boss 1 | `isengardmagicroo` |
| Card Mennard | `arohirrimsold006` | 201 | 167 | -17% | hit_points | `rohirrimlongswor` 2,178,030 | +9 | 1 | boss 1 -> boss 1 | `edoras` |
| Dol - Guldur Smithy | `dolguldursmi` | 168 | 134 | -20% | hit_points | `` 0 | +93 | 1 | - -> - |  |
| Greater Elven Watcher | `greaterelvenw0_2` | 130 | 97 | -25% | hit_points | `arrowoftheargent` 166,617 | +28 | 6 | normal 2 -> normal 2 | `lothlorienflets`, `lothloriennorth` |
| Eowyn's Personal Guard | `helmsdeepguar0_2` | 250 | 217 | -13% | hit_points | `` 0 | +100 | 5 | normal 1 -> normal 1 | `area008` |
| Gate Shaman - Mordor Black Gate | `creature001_2` | 212 | 182 | -14% | hit_points | `` 0 | +123 | 2 | elite 1 -> elite 1 | `blackgatge` |
| Numarok The Black Hand | `cultmember002_2` | 130 | 106 | -18% | hit_points | `wspmka008` 1,102,154 | -29 | 1 | boss 1 -> boss 1 | `area078` |
| Numanan Numerocks Second Hand | `cultmember002_3` | 130 | 106 | -18% | hit_points | `wspmka008` 1,102,154 | -29 | 1 | boss 1 -> boss 1 | `carndumcity` |
| Guardian of Henneth | `guardianofhennet` | 225 | 248 | +10% | hit_points | `graceofithilien` 1,540,154 | +123 | 5 | normal 1 -> normal 1 | `hennethannun002` |
| Nazgûl Watcher | `creature004_2` | 48 | 27 | -44% | hit_points | `` 0 | +0 | 6 | normal 1 -> normal 1 | `nazgulguildhouse` |
| Black Numenorean Militia | `numenoreanmili_3` | 50 | 36 | -28% | abilities | `` 0 | +17 | 7 | normal 2 -> normal 2 | `mountgundabad001`, `mountgundabadlev` |
| Greater Elven Watcher | `greaterelvenw001` | 102 | 113 | +11% | hit_points | `loriengarb003` 401,402 | +28 | 9 | normal 3 -> normal 3 | `lothlorienflets`, `lothloriennorth`, `rivendellupperha` |
| Azagoth | `azagoth` | 37 | 47 | +27% | hit_points | `flameofudun` 1,176,154 | +1 | 1 | elite 1 -> elite 1 | `ruinsofannuminas` |
| Gondorian Bowman | `gondorianguar003` | 82 | 92 | +12% | hit_points | `twinkle` 1,111,590 | +27 | 15 | normal 2 -> normal 2 | `minastirith`, `minastirithgates` |
| Beorning (Shifted) | `bearbeorning001` | 65 | 56 | -14% | hit_points | `cloakoflothlorie` 129,960 | +0 | 3 | normal 1 -> normal 1 | `beorn` |
| Uruk Hai White Hand's Chosen | `urukai008_2` | 50 | 41 | -18% | hit_points | `` 0 | +8 | 1 | normal 1 -> normal 1 | `toweroforthanc` |
| Beorning | `beorning001` | 53 | 45 | -15% | hit_points | `cloakoflothlorie` 129,960 | +0 | 5 | normal 1 -> normal 1 | `beorn` |
| Gwathdor Wizard | `gwathsorcerer` | 78 | 86 | +10% | saves | `gwatwizrobe` 1,053,815 | +0 | 5 | normal 1 -> normal 1 | `gwathwest` |
| Mount Doom Skeleton Monk | `skelchief001` | 50 | 58 | +16% | abilities | `doomstouch` 400,001 | +0 | 2 | normal 1 -> normal 1 | `mountdoom002` |
| Zombie of Dol Guldur | `zombieofdolguldu` | 75 | 83 | +11% | hit_points | `zombieflesh` 344,888 | +0 | 1 | normal 1 -> normal 1 | `dolguldur` |
| Black Numenorean Priestess | `drowcler024_2` | 46 | 39 | -15% | hit_points | `it_mpotion029` 1,320 | +0 | 2 | normal 1 -> normal 1 | `carndumtemple` |
| Black Numenorean Priestess | `drowcler024_3` | 46 | 39 | -15% | hit_points | `it_mpotion029` 1,320 | +0 | 7 | normal 2 -> normal 2 | `mountgundabad001`, `mountgundabadlev` |
| Elf Ranger | `elfranger016` | 65 | 72 | +11% | hit_points | `bowofsecrecy` 1,124,714 | +2 | 6 | normal 2 -> normal 2 | `rivendell`, `thevalleyofriven` |
| Unnamed Horror | `unnamedhorror` | 54 | 61 | +13% | hit_points | `undeadheart` 3,840,901 | -125 | 1 | normal 1 -> normal 1 | `area018` |
| White Widow | `spidgiant002` | 39 | 45 | +15% | abilities | - | +0 | 9 | normal 1 -> normal 1 | `oldforest001` |
| Thing of the Dark | `thingofthedark` | 40 | 46 | +15% | hit_points | `shadowdecayer` 3,821,130 | -125 | 8 | normal 2 -> normal 2 | `area018`, `forgottenking` |
| Appearance Lizard | `appearancelizard` | 33 | 38 | +15% | hit_points | - | +0 | 1 | - -> - |  |
| Black Numenorean Militia | `numenoreanmili_2` | 35 | 30 | -14% | abilities | `nw_it_mpotion013` 120 | +11 | 16 | normal 5 -> normal 5 | `carndum`, `carndumcity`, `carndumsmithy`, `carndumtemple` ... |
| Spider-Queen | `spiderboss001` | 27 | 32 | +19% | abilities | - | -17 | 24 | elite 3/normal 3 -> elite 3/normal 3 | `mirkwoodcentral`, `mirkwoodcentrale`, `mirkwoodcentrals`, `mirkwoodeast` ... |
| Dunland Shaman | `uthgard006_2` | 48 | 43 | -10% | hit_points | `nw_it_mpotion016` 120 | -15 | 1 | normal 1 -> normal 1 | `toweroforthanc` |
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
| Mirkwood: Dol Guldur (`dolguldur`) | 45 | 46 | 11 |
| Angmar Dungeon (`angmardungeon`) | 48 | 51 | 8 |
| Mount Doom: Grand Hall (`area014`) | 54 | 55 | 8 |
| Mirkwood: Thranduil's Hall (`thranduilshall`) | 40 | 35 | 7 |
| Bag End (`bagend001`) | 47 | 49 | 4 |
| Caves of Dol Guldur (`cavesofdolguldur`) | 45 | 46 | 4 |
| The Cirith Ungol Pass (`thecirithungolpa`) | 42 | 44 | 4 |
| Carn Dum: Numerok's Den (`area078`) | 38 | 36 | 2 |
| House of Nazgûl (`nazgulguildhouse`) | 30 | 20 | 1 |
| Mirkwood: Crypt Chamber (`area003`) | 49 | 50 | 0 |
| Mount Doom: Halls of Sauron  (`area016`) | 47 | 46 | 0 |
| Dimholt: The Gate of the Dead (`area018`) | 31 | 32 | 0 |
| Mirkwoods - Halls of Greenleafs (`area023`) | 55 | 56 | 0 |
| Weather Top's Hidden Court (`area028`) | 56 | 55 | 0 |
| Dol Guldur:  Tower Of Black Magic  Nazgul Quaters (`area031`) | 54 | 55 | 0 |
| Beorn (`beorn`) | 31 | 30 | 0 |
| Morannon - The Black Gate (`blackgatge`) | 39 | 38 | 0 |
| Carn Dum (`carndum`) | 26 | 22 | 0 |
| Carn Dum: City (`carndumcity`) | 28 | 26 | 0 |
| Carn Dum: Smithy (`carndumsmithy`) | 26 | 22 | 0 |
| Chamber of Records Wlkwy (`chamberofrecords`) | 6 | 5 | 0 |
| Dol Guldur:  Tower Of Black Magic Depths (`dolguldurcast001`) | 49 | 55 | 0 |
| Dol Guldur:  Tower Of Black Magic Main Hall (`dolguldurcastle`) | 48 | 53 | 0 |
| Durin's Bridge (`durinsbridge`) | 6 | 5 | 0 |
| The Halls of Truth (`halloftruth`) | 33 | 31 | 0 |
| Helm's Deep (`helmsdeep001`) | 39 | 45 | 0 |
| Isengard (Outerrim) (`isengardouterrim`) | 35 | 36 | 0 |
| Minas Tirith: City (`minastirith`) | 33 | 34 | 0 |
| Minas Tirith: Gates (`minastirithgates`) | 33 | 34 | 0 |
| Minas Tirith: Temple (`minastirithtemp`) | 48 | 45 | 0 |
| Mirkwood: Central East (`mirkwoodcentrale`) | 22 | 24 | 0 |
| Mirkwood: Central South (`mirkwoodcentrals`) | 22 | 24 | 0 |
| Mirkwood: North (`mirkwoodnorth`) | 22 | 24 | 0 |
| Old Forest (`oldforest001`) | 29 | 30 | 0 |
| Bilbo's House (`shirebilbohouse`) | 47 | 49 | 0 |
| Moria: The Balrog of Moria (`thebalrogofmoria`) | 49 | 55 | 0 |
| The Dimrill Stair (`thedimrillstair`) | 6 | 5 | 0 |
| The Gates of Moria (`thegatesofmoria`) | 6 | 5 | 0 |
| Tower of the High Wizard: The High Wizard's Chamber (`towerofthehighwi`) | 55 | 51 | 0 |
| Mirkwood: Forest of Greenleaves (`woodoflegolas`) | 36 | 39 | 0 |

