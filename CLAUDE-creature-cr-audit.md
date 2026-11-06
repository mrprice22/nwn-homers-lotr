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
| all with every item resolved | 825 | 349 (42%) | 425 | 580 (70%) | 668 |
| CRAdjust = 0 | 475 | 265 (56%) | 298 | 365 (77%) | 411 |
| CRAdjust != 0 | 350 | 84 (24%) | 127 | 215 (61%) | 257 |

5 blueprints have an item the formula cannot price (a hak-only item); they are left out.

## Summary of a full resync (every spawned non-utility blueprint off by more than 10%)

| | count |
|---|---|
| drifted blueprints that spawn | 136 |
| ... utility NPCs (`q_`, `cbd_`, `cp_`, `dmfi_`, `ds_`), CR probably hand-set on purpose | 1 |
| ... drift driven mostly by **item value** | 65 |
| ... other | 70 |
| CR would rise / fall | 89 / 47 |
| boss board: joins / leaves | 2 / 3 |
| area loot levels that change | 50 |
| loot-class changes (slots) | normal->elite 18, elite->normal 6 |

**Boss board changes:** joins `raitheen` (Raitheen the Watcher), `unnamedhorror` (Unnamed Horror); leaves `creature007` (Khamûl The Ringwraith), `creature007_2` (Khamûl The Ringwraith), `legolasgreenl001` (Legolas Greenleaf -  Silvan Prince of Mirkwood).

## Utility NPCs (likely hand-set - probably leave alone)

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| Combat Dummy | `cbd_dummy` | 1 | 444 | +44300% | hit_points | - | +0 | 1 | normal 1 -> normal 1 | `bree` |

## Drift driven by item value

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| Legolas Greenleaf -  Silvan Prince of Mirkwood | `legolasgreenl001` | 1418 | 180363 | +12620% | items | `arrowsoflegolas` 818,314,893 | +124 | 1 | boss 1 -> boss 1 | `area023` |
| Khamûl The Ringwraith | `creature007` | 965 | 32644 | +3283% | items | `shadowoftheeast` 226,217,500 | +123 | 1 | boss 1 -> boss 1 | `area031` |
| Khamûl The Ringwraith | `creature007_2` | 839 | 30358 | +3518% | items | `shadowoftheeast` 226,217,500 | +0 | 1 | boss 1 -> boss 1 | `carndumthrone` |
| Drider Mage | `drowmage003` | 361 | 16155 | +4375% | items | `boltofdrider001` 1,675,535,994 | +125 | 8 | normal 2 -> elite 2 | `angmardungeon`, `area009` |
| Arwen, The Evenstar | `creature005` | 767 | 5632 | +634% | items | `wammar048` 47,436,840 | +125 | 1 | boss 1 -> boss 1 | `rivendellupperha` |
| Maggot Farmer | `maggotfarmer` | 436 | 4152 | +852% | items | `maggotswam001` 100,048,806 | +125 | 1 | boss 1 -> boss 1 | `bywater` |
| Rohirrim Archer | `rohirrimbowme001` | 222 | 3497 | +1475% | items | `item097` 33,092,136 | +125 | 11 | normal 2 -> elite 1/normal 1 | `area013`, `pathtohelmsdeep` |
| The Balrog of Moria | `azagoth001` | 555 | 3308 | +496% | items | `orcseeker` 100,806,250 | +125 | 1 | boss 1 -> boss 1 | `thebalrogofmoria` |
| Theoden's Chosen | `creature016` | 9540 | 6965 | -27% | items | `it_mneck002` 246,016,001 | +125 | 1 | boss 1 -> boss 1 | `area013` |
| Mountain Giant | `mountaingiant` | 68 | 2114 | +3009% | items | `giantsbullets` 59,795,010 | +0 | 7 | normal 1 -> elite 1 | `emynmuil` |
| Rohirrim Mage | `rohirrimbowme002` | 268 | 2072 | +673% | items | `elitebolt` 33,088,176 | +120 | 2 | normal 2 -> elite 1/normal 1 | `area013`, `pathtohelmsdeep` |
| Mirkwood Forest Walker | `mirkwoodforestwa` | 107 | 1889 | +1665% | items | `wingsofmirkwood` 49,063,806 | +0 | 7 | normal 1 -> normal 1 | `woodoflegolas` |
| Archer of Dol Guldur | `archerofdolguldu` | 234 | 1571 | +571% | items | `deadlycaress2` 34,917,597 | +1 | 10 | normal 2 -> elite 2 | `cavesofdolguldur`, `dolguldur` |
| Angmar | `angmar` | 637 | 1971 | +209% | items | `wammar050` 41,692,563 | +125 | 1 | boss 1 -> boss 1 | `area009` |
| Greater Elven Watcher | `greaterelvenw001` | 102 | 1275 | +1150% | items | `arrowoftheargent` 16,495,083 | +28 | 9 | normal 3 -> elite 2/normal 1 | `lothlorienflets`, `lothloriennorth`, `rivendellupperha` |
| Weathertop King | `weathertopkin004` | 3400 | 2232 | -34% | items | `thebladeofthe005` 54,243,974 | -120 | 1 | boss 1 -> boss 1 | `area028` |
| Guardian of Henneth | `guardianofhennet` | 225 | 1280 | +469% | items | `deadlycaress` 23,168,673 | +123 | 5 | normal 1 -> normal 1 | `hennethannun002` |
| Weathertop Queen | `weathertopque003` | 3100 | 2110 | -32% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area028` |
| Gloin King Under the Mountain | `adwarfguardia001` | 799 | 1713 | +114% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `lonelymountainma` |
| Dol - Guldur  Elite Bow Man | `mordororcbowm005` | 105 | 1011 | +863% | items | `043` 23,394,987 | +10 | 10 | normal 1 -> elite 1 | `dolguldurcity` |
| Gothmog Lord of Barad-Dur | `thehighmageofbar` | 604 | 1392 | +130% | items | `bossring` 70,478,127 | -125 | 1 | boss 1 -> boss 1 | `baraddurkeep` |
| Sauron's Chosen Minion | `sauronschosen005` | 551 | 1246 | +126% | items | `bossring` 70,478,127 | +125 | 4 | normal 2 -> normal 2 | `dolguldurcast001`, `dolguldurcastle` |
| Barad Berserker | `baradberserker` | 246 | 916 | +272% | items | `bossring` 70,478,127 | +125 | 6 | - -> - |  |
| Greater Black Numenorean Assassin | `numenoreanpat001` | 424 | 1063 | +151% | items | `bossring` 70,478,127 | +125 | 8 | normal 1 -> normal 1 | `angmardungeon` |
| Eowyn the Shieldmaiden | `eowyntheshieldma` | 693 | 1327 | +91% | items | `bossring` 70,478,127 | +76 | 1 | boss 1 -> boss 1 | `area008` |
| Elf Ranger | `elfranger016` | 65 | 676 | +940% | items | `wammar053` 4,292,838 | +2 | 6 | normal 2 -> elite 2 | `rivendell`, `thevalleyofriven` |
| Elite Rohirrim Soldier | `arohirrimsold004` | 158 | 765 | +384% | items | `bossring` 70,478,127 | +1 | 2 | elite 1 -> elite 1 | `edoras` |
| Uruk Hai Bowman | `urukaibowman` | 92 | 694 | +654% | items | `orcquivers` 21,323,313 | +13 | 8 | elite 1/normal 1 -> elite 2 | `ettenmoors`, `isengardouterrim` |
| Archer Of Mordor | `archerofmordor_2` | 135 | 537 | +298% | items | `wammar055` 6,078,105 | +3 | 12 | normal 1 -> elite 1 | `blackgatge` |
| Witch King Leader of The Nine | `witchking` | 1198 | 1561 | +30% | items | `bossring_ci` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `thewitchkingsthr` |
| Drider Militia | `drowfight021` | 650 | 941 | +45% | items | `headsplitter004` 37,613,486 | +11 | 16 | elite 2/normal 2 -> elite 2/normal 2 | `angmardungeon`, `area009`, `greateastroadd`, `theangmarmountai` |
| Gwathdor Lord of the Dark Arts | `gwathdorlord001` | 1615 | 1893 | +17% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `gwaththrone` |
| Greater Elven Watcher | `greaterelvenw0_2` | 130 | 387 | +198% | items | `arrowoftheargent` 16,495,083 | +28 | 6 | normal 2 -> normal 2 | `lothlorienflets`, `lothloriennorth` |
| Radagast's Elite Guard | `creature014` | 658 | 880 | +34% | items | `wswmgs009` 41,992,116 | +125 | 4 | normal 1 -> normal 1 | `rhosgobeltower` |
| Aragorn Son of Arathorn | `aragornsonofarat` | 712 | 931 | +31% | items | `044` 23,394,987 | +125 | 1 | boss 1 -> boss 1 | `minastirithgates` |
| Saruman the White | `sarumanthewhi001` | 627 | 831 | +33% | items | `044` 23,394,987 | +0 | 1 | boss 1 -> boss 1 | `towerofothancsar` |
| Shadow Priestess of Dol Guldur | `shadowlordof001` | 463 | 663 | +43% | items | `044` 23,394,987 | +125 | 1 | boss 1 -> boss 1 | `cavesofdolguldur` |
| Faramir, Prince of Ithillien | `creature002` | 451 | 650 | +44% | items | `044` 23,394,987 | +0 | 1 | boss 1 -> boss 1 | `citidelofstars` |
| Underlord of Sauron | `mummyboss001` | 1697 | 1894 | +12% | items | `mindmelter001` 49,651,898 | +125 | 2 | normal 1 -> normal 1 | `area014` |
| Galadriel | `galadriel` | 150 | 343 | +129% | items | `044` 23,394,987 | +0 | 1 | boss 1 -> boss 1 | `lothlorien` |
| Drider Priestess | `drowcler026` | 460 | 652 | +42% | items | `044` 23,394,987 | +84 | 7 | normal 2 -> normal 2 | `angmardungeon`, `area009` |
| The Mighty Smaug | `themightysmag002` | 1048 | 1235 | +18% | items | `bossring` 70,478,127 | +123 | 1 | boss 1 -> boss 1 | `darkcavern` |
| Sauron The Abhorred | `creature019` | 1768 | 1949 | +10% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area016` |
| Glorfindel | `glorfindel002` | 323 | 495 | +53% | items | `wswmls007` 6,609,654 | +112 | 1 | boss 1 -> boss 1 | `thevalleyofriven` |
| Denethor, Steward of Gondor | `creature003` | 1459 | 1617 | +11% | items | `bossring` 70,478,127 | +125 | 1 | boss 1 -> boss 1 | `area005` |
| Celeborn | `greaterelvenw003` | 250 | 384 | +54% | items | `infernoarrows002` 4,301,748 | +101 | 1 | boss 1 -> boss 1 | `lothlorienflets` |
| Black Numenorean Archer | `blacknumenoreana` | 80 | 194 | +142% | items | `boltoftheblackel` 2,165,031 | +22 | 6 | elite 1/normal 1 -> elite 2 | `greateastroadd`, `theangmarmountai` |
| Black Numenorean Archer | `blacknumenorea_2` | 80 | 172 | +115% | items | `boltoftheblackel` 2,165,031 | +22 | 2 | elite 1 -> elite 1 | `carndum` |
| Nazgul | `thundergut` | 255 | 330 | +29% | items | `item057` 4,133,708 | +95 | 1 | elite 1 -> elite 1 | `area010` |
| Gondorian Bowman | `gondorianguar003` | 82 | 148 | +80% | items | `boltoftheblackel` 2,165,031 | +27 | 15 | normal 2 -> normal 2 | `minastirith`, `minastirithgates` |
| Gimli | `gimli_2` | 418 | 356 | -15% | items | `item044` 12,860,130 | +125 | 1 | boss 1 -> boss 1 | `halloftruth` |
| Mount Doom Skeleton | `skeleton003` | 178 | 240 | +35% | items | `waxmbt005` 6,994,508 | +125 | 8 | normal 1 -> elite 1 | `mountdoom002` |
| Bowman of The Deep | `bowmanofthede001` | 145 | 205 | +41% | items | `054` 1,325,390 | +39 | 9 | normal 1 -> normal 1 | `helmsdeep001` |
| Mordor Orc Snaker Soldier | `mordororcsnake` | 131 | 181 | +38% | items | `mordoraxe` 1,922,800 | +62 | 12 | normal 3 -> normal 3 | `cirithungol`, `eredduathroada`, `thecirithungolpa` |
| Dol Guldur Orc General | `akhorahil004` | 277 | 326 | +18% | items | `127` 7,317,142 | +125 | 1 | boss 1 -> boss 1 | `dolguldurcity` |
| Fist of Sauron | `creature008` | 289 | 338 | +17% | items | `item020` 4,515,843 | +122 | 28 | - -> - |  |
| Mordor Orc Bowman | `mordororcbowman` | 171 | 220 | +29% | items | `kukri051` 1,993,976 | +124 | 13 | normal 3 -> normal 3 | `eredduathroada`, `orcarmory`, `thecirithungolpa` |
| Smithey the Sneak | `halfmerc002` | 13 | 55 | +323% | items | `scimitarofthequi` 7,302,390 | +0 | 1 | elite 1 -> elite 1 | `sharkeyschamber` |
| Gondorian Bowman | `gondorianguar0_4` | 85 | 124 | +46% | items | `boltoftheblackel` 2,165,031 | +27 | 1 | boss 1 -> boss 1 | `watchmandefender` |
| Mebridiel Relein | `mebridiel` | 12 | 20 | +67% | items | `dart5` 600,200 | +0 | 1 | - -> - |  |
| A Forgotten Soldier | `aforgottensoldio` | 58 | 65 | +12% | items | `dunharrowblade` 2,723,250 | -100 | 7 | normal 2 -> normal 2 | `area018`, `forgottenking` |
| Forgotten Warrior | `forgottenwarrior` | 64 | 71 | +11% | items | `dunharrowkama` 4,190,704 | -125 | 15 | normal 3 -> normal 3 | `area018`, `dunharrow`, `forgottenking` |
| Frust Ice Stone | `gntfrost010` | 24 | 31 | +29% | items | `wdbmsw007` 750,980 | +0 | 1 | normal 1 -> elite 1 | `icequeenlair` |
| Grokul Head Master | `minchief001` | 24 | 28 | +17% | items | `brainhew` 129,644 | +4 | 1 | elite 1 -> elite 1 | `planeoftherender` |
| Goblin Gate Peon | `bugbearb001` | 2 | 4 | +100% | items | `wammbo009` 392,040 | +0 | 29 | normal 6 -> normal 6 | `goblingategreate`, `goblingatelesser`, `goblingatemines`, `goblintownmainha` ... |

## Other drift (stats, levels, HP changed since the last toolset save)

XP note: kill XP scales with stored CR, so a large rise is a large XP rise.

| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |
|---|---|---|---|---|---|---|---|---|---|---|
| <c¥  >»[The]«</c> <c¥  >»[Forger]«</c> | `methonashforge` | 17427 | 86 | -100% | saves | `` 0 | +0 | 1 | - -> - |  |
| <c¥  >»[The]«</c> <c¥  >»[Well-Mart]«</c> | `methonashmart` | 17427 | 86 | -100% | saves | `` 0 | +0 | 1 | - -> - |  |
| High Wizard of Gondor | `highwizardofgo_2` | 1795 | 732 | -59% | hit_points | `bastardofthehobb` 5,473,214 | +125 | 1 | boss 1 -> boss 1 | `towerofthehighwi` |
| Temple Mistress | `templemistress_2` | 980 | 243 | -75% | hit_points | `amuletofdirep002` 187,211 | +0 | 1 | boss 1 -> boss 1 | `blackgatge` |
| Radagast the Brown | `radagastthebro_2` | 1086 | 791 | -27% | hit_points | `lesserrobe3or004` 9,830,723 | +124 | 1 | boss 1 -> boss 1 | `rhosgobeltower` |
| Fell Beast | `badass_2` | 333 | 75 | -77% | abilities | `` 0 | +0 | 1 | boss 1 -> boss 1 | `kallristcryptlow` |
| The Rancid Skinner Green Mortal of Khamul | `creature023_2` | 810 | 575 | -29% | hit_points | `wspmku011` 8,522,972 | +122 | 1 | boss 1 -> boss 1 | `dolguldurcast001` |
| Dol Guldur Gate Keeper | `dolguldurgatekee` | 696 | 914 | +31% | hit_points | `044` 23,394,987 | +125 | 1 | elite 1 -> normal 1 | `dolguldur` |
| High Priest of Gondor | `shopkeep002_2` | 447 | 245 | -45% | hit_points | `tearhuanch2` 100,702 | +50 | 1 | boss 1 -> boss 1 | `minastirithtemp` |
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
| Éothain Captian of Helm's Deep | `creature017_2` | 440 | 340 | -23% | hit_points | `it_mpotion013` 5,280 | +5 | 1 | boss 1 -> boss 1 | `helmsdeep001` |
| Sauron's Personal Gaurds | `guardsofconsta_2` | 410 | 321 | -22% | hit_points | `x2_it_mring029` 357,012 | +125 | 7 | normal 1 -> normal 1 | `area016` |
| Dol Guldur Gate Keeper | `dolguldurgatek_2` | 701 | 621 | -11% | hit_points | `cloth027` 1,797,761 | +125 | 1 | elite 1 -> normal 1 | `dolguldur` |
| Deekin the General | `bauglirthegene_2` | 336 | 258 | -23% | hit_points | `x2_it_mneck022` 98,010 | -15 | 1 | boss 1 -> boss 1 | `orcarmory` |
| Shadow Lord of Dol Guldur | `shadowlordof_2` | 660 | 584 | -12% | hit_points | `item086` 9,112,580 | +124 | 1 | boss 1 -> boss 1 | `dolguldur` |
| Basilisk King | `basilisk008` | 564 | 637 | +13% | hit_points | `basilisktail006` 7,567,389 | +0 | 1 | boss 1 -> boss 1 | `area003` |
| Mutated Basilisk | `basilisk005` | 445 | 508 | +14% | hit_points | `ancientmace005` 7,365,954 | +0 | 3 | normal 1 -> normal 1 | `area002` |
| Nature's Defender | `forestwalkerof_2` | 157 | 96 | -39% | hit_points | `` 0 | +0 | 2 | normal 1 -> normal 1 | `thranduilshall` |
| Mutated Basilisk | `basilisk006` | 445 | 505 | +13% | hit_points | `ancientbow009` 7,197,150 | +0 | 3 | normal 1 -> normal 1 | `area002` |
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
| Eowyn's Personal Guard | `helmsdeepguar0_2` | 250 | 217 | -13% | hit_points | `` 0 | +100 | 5 | normal 1 -> normal 1 | `area008` |
| Gate Shaman - Mordor Black Gate | `creature001_2` | 212 | 182 | -14% | hit_points | `` 0 | +123 | 2 | elite 1 -> elite 1 | `blackgatge` |
| Numarok The Black Hand | `cultmember002_2` | 130 | 106 | -18% | hit_points | `wspmka008` 1,102,154 | -29 | 1 | boss 1 -> boss 1 | `area078` |
| Numanan Numerocks Second Hand | `cultmember002_3` | 130 | 106 | -18% | hit_points | `wspmka008` 1,102,154 | -29 | 1 | boss 1 -> boss 1 | `carndumcity` |
| Nazgûl Watcher | `creature004_2` | 48 | 27 | -44% | hit_points | `` 0 | +0 | 6 | normal 1 -> normal 1 | `nazgulguildhouse` |
| Black Numenorean Militia | `numenoreanmili_3` | 50 | 36 | -28% | abilities | `` 0 | +17 | 7 | normal 2 -> normal 2 | `mountgundabad001`, `mountgundabadlev` |
| Azagoth | `azagoth` | 37 | 47 | +27% | hit_points | `flameofudun` 1,176,154 | +1 | 1 | elite 1 -> elite 1 | `ruinsofannuminas` |
| Beorning (Shifted) | `bearbeorning001` | 65 | 56 | -14% | hit_points | `cloakoflothlorie` 129,960 | +0 | 3 | normal 1 -> normal 1 | `beorn` |
| Uruk Hai White Hand's Chosen | `urukai008_2` | 50 | 41 | -18% | hit_points | `` 0 | +8 | 1 | normal 1 -> normal 1 | `toweroforthanc` |
| Beorning | `beorning001` | 53 | 45 | -15% | hit_points | `cloakoflothlorie` 129,960 | +0 | 5 | normal 1 -> normal 1 | `beorn` |
| Gwathdor Wizard | `gwathsorcerer` | 78 | 86 | +10% | saves | `gwatwizrobe` 1,053,815 | +0 | 5 | normal 1 -> normal 1 | `gwathwest` |
| Mount Doom Skeleton Monk | `skelchief001` | 50 | 58 | +16% | abilities | `doomstouch` 400,001 | +0 | 2 | normal 1 -> normal 1 | `mountdoom002` |
| Zombie of Dol Guldur | `zombieofdolguldu` | 75 | 83 | +11% | hit_points | `zombieflesh` 344,888 | +0 | 1 | normal 1 -> normal 1 | `dolguldur` |
| Black Numenorean Priestess | `drowcler024_2` | 46 | 39 | -15% | hit_points | `it_mpotion029` 1,320 | +0 | 2 | normal 1 -> normal 1 | `carndumtemple` |
| Black Numenorean Priestess | `drowcler024_3` | 46 | 39 | -15% | hit_points | `it_mpotion029` 1,320 | +0 | 7 | normal 2 -> normal 2 | `mountgundabad001`, `mountgundabadlev` |
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
| Mirkwood: Dol Guldur (`dolguldur`) | 45 | 50 | 11 |
| Angmar Dungeon (`angmardungeon`) | 48 | 55 | 8 |
| Mount Doom: Grand Hall (`area014`) | 54 | 55 | 8 |
| Mirkwood: Thranduil's Hall (`thranduilshall`) | 40 | 35 | 7 |
| Ered Duath Road: A (`eredduathroada`) | 38 | 43 | 6 |
| Bag End (`bagend001`) | 47 | 49 | 4 |
| Caves of Dol Guldur (`cavesofdolguldur`) | 45 | 46 | 4 |
| The Cirith Ungol Pass (`thecirithungolpa`) | 42 | 45 | 4 |
| Carn Dum: Numerok's Den (`area078`) | 38 | 36 | 2 |
| Path To Helm's Deep (`pathtohelmsdeep`) | 45 | 56 | 2 |
| House of Nazgûl (`nazgulguildhouse`) | 30 | 20 | 1 |
| Mirkwood: Crypt Chamber (`area003`) | 49 | 50 | 0 |
| Angmar's Lair (`area009`) | 49 | 55 | 0 |
| Mount Doom: Halls of Sauron  (`area016`) | 47 | 46 | 0 |
| Dimholt: The Gate of the Dead (`area018`) | 31 | 32 | 0 |
| Mirkwoods - Halls of Greenleafs (`area023`) | 55 | 60 | 0 |
| Weather Top's Hidden Court (`area028`) | 56 | 55 | 0 |
| Dol Guldur:  Tower Of Black Magic  Nazgul Quaters (`area031`) | 54 | 60 | 0 |
| Beorn (`beorn`) | 31 | 30 | 0 |
| Morannon - The Black Gate (`blackgatge`) | 39 | 38 | 0 |
| Carn Dum (`carndum`) | 26 | 22 | 0 |
| Carn Dum: City (`carndumcity`) | 28 | 26 | 0 |
| Carn Dum: Smithy (`carndumsmithy`) | 26 | 22 | 0 |
| Chamber of Records Wlkwy (`chamberofrecords`) | 6 | 5 | 0 |
| Dol Guldur:  Tower Of Black Magic Depths (`dolguldurcast001`) | 49 | 55 | 0 |
| Dol Guldur:  Tower Of Black Magic Main Hall (`dolguldurcastle`) | 48 | 53 | 0 |
| Dol Guldur City (`dolguldurcity`) | 45 | 46 | 0 |
| Durin's Bridge (`durinsbridge`) | 6 | 5 | 0 |
| The Halls of Truth (`halloftruth`) | 33 | 31 | 0 |
| Helm's Deep (`helmsdeep001`) | 39 | 45 | 0 |
| Henneth Annun (`hennethannun002`) | 45 | 55 | 0 |
| Isengard (Outerrim) (`isengardouterrim`) | 35 | 45 | 0 |
| Lothlorien: Flets (`lothlorienflets`) | 35 | 47 | 0 |
| Lothlorien: North (`lothloriennorth`) | 35 | 47 | 0 |
| Minas Tirith: City (`minastirith`) | 33 | 40 | 0 |
| Minas Tirith: Gates (`minastirithgates`) | 33 | 40 | 0 |
| Minas Tirith: Temple (`minastirithtemp`) | 48 | 45 | 0 |
| Mirkwood: Central East (`mirkwoodcentrale`) | 22 | 24 | 0 |
| Mirkwood: Central South (`mirkwoodcentrals`) | 22 | 24 | 0 |
| Mirkwood: North (`mirkwoodnorth`) | 22 | 24 | 0 |
| Old Forest (`oldforest001`) | 29 | 30 | 0 |
| Rhosgobel:  Tower (`rhosgobeltower`) | 50 | 53 | 0 |
| Rivendell Upper Halls (`rivendellupperha`) | 41 | 55 | 0 |
| Bilbo's House (`shirebilbohouse`) | 47 | 49 | 0 |
| Moria: The Balrog of Moria (`thebalrogofmoria`) | 49 | 56 | 0 |
| The Dimrill Stair (`thedimrillstair`) | 6 | 5 | 0 |
| The Gates of Moria (`thegatesofmoria`) | 6 | 5 | 0 |
| Tower of the High Wizard: The High Wizard's Chamber (`towerofthehighwi`) | 55 | 51 | 0 |
| Minas Tirith: Watchman Defender's Head Quarters (`watchmandefender`) | 33 | 35 | 0 |
| Mirkwood: Forest of Greenleaves (`woodoflegolas`) | 36 | 55 | 0 |

