// hw_areas_inc - Harvest of Shadows area table (generated).
//
// HW_AreaTier(resref): 0 = peaceful area (town pumpkins that decay), 1..6 =
// hostile area tier from the median CR of its hostile spawns (cursed,
// persistent pumpkins scaled to it). HW_BossHome(i): "resref|area|x|y|z" for
// each Roll of the Fallen boss, where its respawning pumpkin ring is planted.
//
// The block below is rewritten by `python3 bin/gen-halloween-areas.py --write`;
// tests/check_halloween_areas.py fails the repack when it is stale. Tune the
// tier cuts and hand overrides in the script, never here.

// BEGIN GENERATED HW AREAS - produced by bin/gen-halloween-areas.py; do not hand-edit.
int HW_AreaTier(string sResRef)
{
    string s = "|" + sResRef + "|";
    if (FindSubString("|area012|billfernyshouse|bree|breecave|breecaverns|breecrypt|breecryptlowerle|chetwood001|goblingatelesser|greateastroada|greateastroadc|greenwaynorth|greenwaysouth|greenwaysoutheas|loogazlair|midgewaterswamp|roadtobaraddur|sharkeyschamber|sharkeysmill|thebarrowdowns|thenorthdowns001|theruinsofdale|thesecretpassofm|thestinkinsewer|tombofgarmir|tombofmendegilat|tombofperan|tombofvinyalonde|", s) >= 0) return 1;
    if (FindSubString("|alterwald|angmar|area004|cardolan|carrok|carrokgreater|carroklesser|celeduinbanks|chamberofrecords|cryptsofthelosts|dunland|dunlandwarparty|durinsbridge|dwarrowdelfea001|dwarrowdelfeast|emynarnen|enchantedcave001|enchantedcave002|ettenmoors|gapofrohaneast|goblingategreate|goblingatemines|goblintownmainha|goblintownwarren|gondoremynarnen|greateastroadb|icequeenlair|kallristcryptlow|kallristcryptupp|kallristdarkrim|kallristeastshor|kallristinner|kallristnorthsho|kallristouterban|kallristwestshor|mirkwoodcentral|mirkwoodeast|mirkwoodwest|mistymountainsa|mistymountainsb|morialevel1cente|oldbackroad|oldforestroad|planeoftherender|ruinsofannuminas|theangmarmountai|thedimrillstair|thegatesofmoria|thetempleofmoran|thetrollshalls|thewold|woldsouth|", s) >= 0) return 2;
    if (FindSubString("|area018|carndum|carndumcity|carndumsmithy|carndumtemple|fangornforest|fangornoutskirts|forgottenking|greateastroadd|mirkwoodcentrale|mirkwoodcentrals|mirkwoodnorth|mountdoom|mountgundabad001|mountgundabadlev|nazgulguildhouse|nindalf|oldforest001|theabyssofmoria|", s) >= 0) return 3;
    if (FindSubString("|area010|carndumthrone|dolguldur001|dunharrow|emynmuil|gwathdorcave|isengardouterrim|kerufallslair|thewitchkingsthr|toweroforthanc|", s) >= 0) return 4;
    if (FindSubString("|area078|balinstomb|blackgatge|deadmarshes|eredduathroada|gwathdoroutskirt|harad|icequeennest|isengardmagicroo|mountdoom002|shelobslair|thecirithungolpa|", s) >= 0) return 5;
    if (FindSubString("|angmardungeon|area002|area003|area007|area009|area014|area016|area023|area025|area028|area031|cavesofdolguldur|cirithungol|darkcavern|dolguldur|dolguldurcast001|dolguldurcastle|dolguldurcity|falseheaven|gondorcrypts|gwathdordeeps|gwaththrone|gwathtomb|gwathwest|heavensdisdain|heavensscorn|hennethannun|isengardinnerrim|northernfores001|northernfores004|northernfores005|northernforestso|orcarmory|rhosgobeltower|thebalrogofmoria|", s) >= 0) return 6;
    return 0;
}

// No pumpkins and no lighting change at all in these areas.
int HW_AreaExcluded(string sResRef)
{
    return FindSubString("|appearancechange|area017|dmcloningchamber|dmcontrolroom|dmeventarea|dmhq|prison|", "|" + sResRef + "|") >= 0;
}

const int HW_BOSS_HOME_COUNT = 80;

string HW_BossHome(int i)
{
    switch (i)
    {
        case 0: return "creature016|area013|24.52|74.70|1.24";
        case 1: return "weathertopkin004|area028|35.17|123.63|1.02";
        case 2: return "weathertopque003|area028|25.14|123.80|1.02";
        case 3: return "summanus|falseheaven|55.19|21.17|0.00";
        case 4: return "gandalf001|shirehobbiton001|45.19|91.35|10.01";
        case 5: return "highwizardofgo_2|towerofthehighwi|9.99|4.97|0.12";
        case 6: return "creature019|area016|20.13|194.01|0.61";
        case 7: return "gwathdorlord001|gwaththrone|52.13|54.93|-0.00";
        case 8: return "creature009|minastirith|94.98|84.89|4.00";
        case 9: return "creature003|area005|15.02|65.05|0.60";
        case 10: return "legolasgreenl001|area023|25.17|35.23|-0.00";
        case 11: return "witchking|thewitchkingsthr|30.11|89.88|0.88";
        case 12: return "radagastthebro_2|rhosgobeltower|14.97|24.89|0.60";
        case 13: return "thecursedone002|forgottenking|44.95|69.05|-0.00";
        case 14: return "themightysmag002|darkcavern|12.31|18.14|-0.00";
        case 15: return "gollum|area007|14.15|45.00|3.00";
        case 16: return "templemistress_2|blackgatge|104.36|67.59|-0.00";
        case 17: return "creature007|area031|34.83|34.72|0.00";
        case 18: return "creature007_2|carndumthrone|40.15|49.52|0.88";
        case 19: return "elrond001_2|rivendellupperha|54.99|23.73|-0.00";
        case 20: return "harethofthehalad|edoras|120.04|70.03|10.60";
        case 21: return "creature023_2|dolguldurcast001|45.04|59.38|1.00";
        case 22: return "adwarfguardia001|lonelymountainma|75.03|123.42|0.60";
        case 23: return "creature005|rivendellupperha|55.04|26.17|-0.00";
        case 24: return "aragornsonofarat|minastirithgates|14.70|44.98|0.75";
        case 25: return "eowyntheshieldma|area008|24.93|80.21|-0.00";
        case 26: return "shadowlordof_2|dolguldur|145.12|130.27|10.00";
        case 27: return "ulmothevalar_2|area022|40.00|39.10|-0.00";
        case 28: return "angmar|area009|35.09|63.88|0.33";
        case 29: return "sarumanthewhi001|towerofothancsar|19.59|60.18|0.36";
        case 30: return "thehighmageofbar|baraddurkeep|64.44|64.91|0.60";
        case 31: return "grimbeorntheo001|beorn|106.00|59.98|2.50";
        case 32: return "basilisk008|area003|44.10|42.65|-0.00";
        case 33: return "azagoth001|thebalrogofmoria|45.45|55.31|1.57";
        case 34: return "highpriestofmora|thetempleofmoran|24.96|45.54|1.57";
        case 35: return "thranduil_2|thranduilshall|80.11|153.02|0.00";
        case 36: return "shadowlordof001|cavesofdolguldur|25.39|13.94|0.01";
        case 37: return "creature002|citidelofstars|40.30|60.04|-0.15";
        case 38: return "shopkeep002_2|minastirithtemp|19.94|26.92|1.34";
        case 39: return "creature017_2|helmsdeep001|45.06|104.73|12.60";
        case 40: return "maggotfarmer|bywater|13.35|48.31|-0.29";
        case 41: return "akhorahil006_2|dolguldurcity|65.12|85.99|-0.00";
        case 42: return "gimli_2|halloftruth|4.97|75.54|-0.00";
        case 43: return "kerufall003|kerufallslair|56.88|190.81|0.00";
        case 44: return "urukai010|isengardouterrim|95.23|87.61|0.01";
        case 45: return "gondorianwiza001|towerofthehig001|24.89|10.15|-0.00";
        case 46: return "gondorianguar005|minastirithgates|96.39|42.49|-0.00";
        case 47: return "theoden002|theodenshall|35.08|54.21|0.39";
        case 48: return "bauglirthegene_2|orcarmory|164.61|34.89|1.57";
        case 49: return "badass_2|kallristcryptlow|94.92|129.17|-0.00";
        case 50: return "glorfindel002|thevalleyofriven|54.86|49.09|-1.06";
        case 51: return "creature013|towerofothancsar|32.48|71.25|-0.00";
        case 52: return "strongminitao002|gwathtomb|60.55|34.90|0.20";
        case 53: return "akhorahil004|dolguldurcity|65.26|118.06|-0.00";
        case 54: return "creature012_2|blackgatge|27.81|53.58|0.00";
        case 55: return "rangerofthe002|rivendell|90.25|30.05|-0.00";
        case 56: return "frost001|emynarnen|25.76|24.97|5.46";
        case 57: return "greaterelvenw003|lothlorienflets|55.09|43.97|-1.06";
        case 58: return "anaraliathewidow|mirkwoodcentrale|70.72|35.03|-1.06";
        case 59: return "kainnatheward001|isengardinnerrim|75.16|71.09|8.00";
        case 60: return "jester|area008|23.77|81.52|-0.00";
        case 61: return "shelob001|shelobslair|89.74|99.10|-0.00";
        case 62: return "adwarfajudica003|thehallsoftruth|40.24|72.80|-0.00";
        case 63: return "arohirrimsold006|edoras|60.12|33.18|5.00";
        case 64: return "gntfire003|mountgundabadlev|54.82|38.94|-0.00";
        case 65: return "garbag|orcarmory|84.18|80.28|0.00";
        case 66: return "trollking|thetrollshalls|81.04|182.36|-0.00";
        case 67: return "galadriel|lothlorien|125.27|100.69|-1.06";
        case 68: return "railthewhiteh001|isengardinnerrim|74.74|38.09|-0.00";
        case 69: return "drgblue004|icequeennest|38.61|41.71|-0.00";
        case 70: return "themutantterror|balinstomb|15.75|29.91|-0.00";
        case 71: return "cultmember002_3|carndumcity|80.12|69.93|-0.00";
        case 72: return "cultmember002_2|area078|75.06|65.27|-0.00";
        case 73: return "urukai013|toweroforthanc|35.28|37.78|0.71";
        case 74: return "drowfight023_2|carndum|74.84|63.53|1.56";
        case 75: return "railthewhiteh003|isengardmagicroo|37.16|29.97|0.00";
        case 76: return "drowrogue024_2|carndumtemple|61.32|24.70|0.00";
        case 77: return "gondorianguar0_4|watchmandefender|42.75|3.55|0.00";
        case 78: return "gondorianguar0_2|watchmandefender|47.17|3.73|-0.00";
        case 79: return "adwarfajudica0_3|halloftruth|34.89|69.06|0.00";
    }
    return "";
}
// END GENERATED HW AREAS
