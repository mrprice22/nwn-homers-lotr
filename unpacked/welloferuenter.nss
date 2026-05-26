// Well of Eru OnEnter
// - Sends a welcome message and gives 3000 starter XP to brand-new characters.
// - Stocks the Donations Chest once per server reset with:
//     * Loot from a randomly selected good-side city (Guardian of Light list)
//     * Loot from a randomly selected evil-side city (Guardian of Darkness list)
//     * Two random bonus items drawn from the full 200k-500k custom item pool

// Creates an item and immediately identifies it.
object CreateIDItem(string sResRef, object oTarget, int nStackSize = 1)
{
    object oItem = CreateItemOnObject(sResRef, oTarget, nStackSize);
    SetIdentified(oItem, TRUE);
    return oItem;
}

// --- bonus item pool: 147 custom items priced 200k-500k GP ---
string GetBonusItemResref(int n)
{
    switch (n)
    {
        case 0:   return "gwathdorhelme002";   // Gwathdor Helmet
        case 1:   return "orcsmasherflail";    // Orc Smasher Flail
        case 2:   return "spectralbrand5";     // Spectral Brand +5
        case 3:   return "beltoftherang001";   // Belt of the Rohirrin Ranger
        case 4:   return "greaterfirearrow";   // Greater Fire Arrows
        case 5:   return "gondorianhelm";      // Gondorian Helm
        case 6:   return "armhe009";           // Shadows' Hood
        case 7:   return "stormstar";          // Storm Star
        case 8:   return "orcquivers";         // Orc Quivers
        case 9:   return "greatshieldofriv";   // Great Shield of Rivendell
        case 10:  return "shroudoffog";        // Shroud of Fog
        case 11:  return "rorammy001";         // The Merrymen's Amulet
        case 12:  return "halberd005";         // Halberd of the Rohir
        case 13:  return "gondorianrobes";     // Gondorian Robes
        case 14:  return "epicring";           // Epic Ring
        case 15:  return "staffoftheram5";     // Staff of the Ram +5
        case 16:  return "138";                // Cloak of Dol Guldur
        case 17:  return "dragonsbreath4";     // Dragon's Breath +4
        case 18:  return "013";                // Armor of The Defender
        case 19:  return "bootsofquicke002";   // Boots of Quickening
        case 20:  return "100";                // Cover of Darkness
        case 21:  return "hindosdoom4";        // Hindo's Doom +4
        case 22:  return "deadlycaress";       // Deadly Caress
        case 23:  return "garbofthewhitebe";   // Garb of the White Ninja
        case 24:  return "043";                // Arrow of the Orc Defender
        case 25:  return "044";                // Arrow of the Orc Defender
        case 26:  return "staffoftheistari";   // Staff of the Istari
        case 27:  return "027";                // Belt of the Dancer
        case 28:  return "item063";            // Belt of Hero's
        case 29:  return "item014";            // Mesh of Barad-Dur
        case 30:  return "mordorbowmana001";   // Mordor Bowman Armor
        case 31:  return "040";                // Ring of the Red Warrior
        case 32:  return "theword001";         // The Paladin's Choice
        case 33:  return "shadowstaff";        // ShadowStaff
        case 34:  return "orcstatbuff";        // Orcish Carapace
        case 35:  return "139";                // Ring of the Black Rider
        case 36:  return "marilithscimitar";   // Marilith Scimitar
        case 37:  return "goreshovel";         // Goreshovel
        case 38:  return "item088";            // Glove of the Hobbits
        case 39:  return "longswordofweath";   // Longsword of Weathertop
        case 40:  return "shieldofthegreyw";   // Shield of the Grey Walker
        case 41:  return "theeyeofmadusa";     // The Eye of Madusa
        case 42:  return "ls_angurvadal";      // Angurvadal
        case 43:  return "049";                // Boots of the Orc Defender
        case 44:  return "039";                // Ring of Speed and Magic Defenses
        case 45:  return "005";                // Shell
        case 46:  return "urukhaiwhitehand";   // Uruk Hai White Mask
        case 47:  return "060";                // Ring of Grimbeorn the Old
        case 48:  return "soulrazor";          // Soulrazor
        case 49:  return "glovstonehear001";   // Greater Gloves of the Stone Heart
        case 50:  return "shieldofthepr001";   // Shield of the Priest
        case 51:  return "gondorianplat001";   // Greater Gondorian Plate
        case 52:  return "daggerofthest001";   // Dagger of the Stars
        case 53:  return "gondorianlongswo";   // Gondorian Longsword
        case 54:  return "fleshoftheund003";   // Rags of an Underlord
        case 55:  return "gondorianlightar";   // Gondorian Light Armor
        case 56:  return "eyesoftheforest";    // Eyes of The Forest
        case 57:  return "wallofpain";         // Wall of Pain
        case 58:  return "wallofpain001";      // Wall of Pain
        case 59:  return "ixilsspike5";        // Ixil's Spike +5
        case 60:  return "001";                // Stave of Slaughter
        case 61:  return "item094";            // Soulkeeper's Robes
        case 62:  return "ashmlw006";          // Shield of the Mage
        case 63:  return "cloakofthebard";     // Cloak of the Bard
        case 64:  return "crossbowofthedef";   // Crossbow of the Defender
        case 65:  return "072";                // Glove of a Devoured Rogue
        case 66:  return "cloakofminastiri";   // Cloak of Minas Tirith
        case 67:  return "009";                // Cloak of Orc
        case 68:  return "crownofweathe004";   // Crown of Weathertop
        case 69:  return "blackheartarmor";    // Blackheart Armor
        case 70:  return "easterlinglaunch";   // Easterling Launcher
        case 71:  return "145";                // Boots of Darkness
        case 72:  return "nazgulamulet";       // Nazgul Amulet
        case 73:  return "elitebolt";          // Elite Bolt
        case 74:  return "item097";            // Elite Shot
        case 75:  return "lavaplate";          // Lava Plate
        case 76:  return "mordororcstandar";   // Ordurin-Forged Plate
        case 77:  return "arrowofhaldir";      // Arrow of Haldir
        case 78:  return "shieldofkings";      // Shield of Kings
        case 79:  return "armhe011";           // Circlet of Flame
        case 80:  return "042";                // Belt of the Orc Defender
        case 81:  return "glamhkama2";         // Kama of the Green Ninja
        case 82:  return "item050";            // Isaac's Ring
        case 83:  return "bowoftheprotecto";   // Bow of the Protector
        case 84:  return "bootsofquicke004";   // Soft Step
        case 85:  return "branchofriven001";   // Branch of Rivendell
        case 86:  return "cloakofdarkness";    // Cloak of Pale Darkness
        case 87:  return "117";                // Messenger's Robe
        case 88:  return "cloth028";           // Leather of Shadows
        case 89:  return "026";                // Mordor Orc Tower Shield
        case 90:  return "gwathdorhelmet";     // Gwathdor Helmet
        case 91:  return "cursedoneshelm";     // Cursed Ones Helm
        case 92:  return "rubyofpower";        // Ruby of Power
        case 93:  return "felloak";            // Felloak
        case 94:  return "amuletofdivin003";   // Amulet of Unfaithful
        case 95:  return "garbofthewhit001";   // Garb of the Green Ninja
        case 96:  return "bootsoftheharper";   // Boots of the Harper Scout
        case 97:  return "wammar051";          // Arwen's Arrow
        case 98:  return "031";                // Helm's Deep Shield
        case 99:  return "023";                // Sarumon's Favor
        case 100: return "thedrowassassin";    // The Drow Assassin belt
        case 101: return "weathertoparrow";    // Road To Helms Arrow
        case 102: return "forestguard";        // Forest Guard shield
        case 103: return "beltofdivinem001";   // Hoarmouth's Sash
        case 104: return "bootsofquickenin";   // Boots of the Rivendell Ranger
        case 105: return "helmoftheride004";   // Helm of the Ridermark Archer
        case 106: return "doomstouch";         // Dooms Touch
        case 107: return "loriengarb003";      // Lorien Garb
        case 108: return "helmoftheriderma";   // Helm of the Elite Rohirrim Soldier
        case 109: return "aarcl008";           // Rohirrin Heavy Armour
        case 110: return "shieldofthero003";   // Shield of the Rohan
        case 111: return "meshoferynlas002";   // Mesh of Eryn Lasgalen
        case 112: return "wswmls003";          // Balor Sword
        case 113: return "item001";            // Plate of The Khamul
        case 114: return "arrowofthranduil";   // Arrow of Thranduil
        case 115: return "gondorianstaff";     // Gondorian Staff
        case 116: return "item021";            // Sauron's Mesh
        case 117: return "wammar050";          // Angmar's Piercing Arrow
        case 118: return "shieldofthedwarv";   // Shield of the Dwarven Cleric
        case 119: return "item034";            // Dragon's Tear
        case 120: return "greaterringof003";   // Greater Ring of Power
        case 121: return "longbowofdeath";     // Longbow of Death
        case 122: return "item111";            // Mordor Archer Bow
        case 123: return "bowofthegaladhri";   // Bow of the Galadhrim
        case 124: return "ringofthedwarf";     // Ring of the Dwarf
        case 125: return "maarcl002";          // Personal Guard Armor
        case 126: return "runehammer5";        // Rune Hammer +5
        case 127: return "hideofthefore";      // Hide of the Forest Spirit
        case 128: return "fistoftheninja";     // Fist of the Ninja
        case 129: return "item133";            // Nature's Wrap
        case 130: return "126";                // Forged Boots of the Orc General
        case 131: return "warhammerofth001";   // Warhammer of the Life Sapper
        case 132: return "ringofdangersens";   // Ring of Danger Sense
        case 133: return "ringofjustice";      // Ring of Justice
        case 134: return "adamantitetow001";   // Fine Dwarven Tower Shield
        case 135: return "arangerdefender";    // A Ranger Defender
        case 136: return "gondorianplat002";   // Gondorian Captain's Plate
        case 137: return "shieldofthero001";   // Shield of The Fleet Elf
        case 138: return "wammar048";          // Epic Arwen Arrow
        case 139: return "cloakofmist";        // Cloak of Mist
        case 140: return "headsplitter002";    // Black Numenorian Slasher
        case 141: return "theelfboneringof";   // The Elfbone Ring of Kiran-Hai
        case 142: return "helmofthehighcle";   // Helm of the High Cleric
        case 143: return "poisontippedf002";   // Poison Tipped Fang
        case 144: return "wingsofmirkwood";    // Wings of Mirkwood
        case 145: return "unholysigil";        // Unholy Sigil
        case 146: return "axeofthewarrioro";   // Axe of the Warrior Orc
    }
    return "";
}

// --- helper: good-side city loot ---
void SpawnGoodCityLoot(object oChest, int nCity)
{
    switch (nCity)
    {
        case 0: // Gondor
            // Gondorian Bowman (8) vs Epic Gondorian Guardsman (2)
            if (Random(2) == 0)
                CreateIDItem("boltoftheblackel", oChest, 40);
            else {
                CreateIDItem("nw_it_mpotion009", oChest);
                CreateIDItem("nw_it_mpotion016", oChest);
            }
            break;

        case 1: // Helms Deep
            // Helm's Deep Elite Guard (6) vs Defender of the Deep (6)
            if (Random(2) == 0) {
                CreateIDItem("nw_it_mpotion003", oChest, 2);
                CreateIDItem("nw_it_mpotion009", oChest, 2);
            } else
                CreateIDItem("012", oChest);      // Helm of the Defender
            break;

        case 2: // Rivendell
            // Forest Guardian of Rivendell (6)
            CreateIDItem("eyesoftheforest", oChest);
            CreateIDItem("nw_it_mbelt021",  oChest);
            break;

        case 3: // Lothlorien
            // Galadhrim Arcane Archer (12) vs Galadhrim Shield Guardian (11)
            if (Random(2) == 0)
                CreateIDItem("wammar029", oChest, 50);    // Cold Arrows
            else {
                CreateIDItem("nw_it_mpotion016", oChest);
                CreateIDItem("nw_it_mpotion005", oChest);
            }
            break;

        case 4: // Edoras
            // Ridermark Guardian (8)
            CreateIDItem("nw_it_mpotion012", oChest);
            CreateIDItem("nw_it_mpotion015", oChest);
            CreateIDItem("nw_it_mpotion009", oChest);
            CreateIDItem("nw_it_mpotion016", oChest);
            break;
    }
}

// --- helper: evil-side city loot ---
void SpawnEvilCityLoot(object oChest, int nCity)
{
    switch (nCity)
    {
        case 0: // Morannan / Black Gate
            // Archer of Mordor (12)
            CreateIDItem("wammar055", oChest, 50);        // Mordor Slayers
            break;

        case 1: // Isengard
            // Dunlending Shock Trooper (5)
            CreateIDItem("nw_it_mpotion004", oChest);
            CreateIDItem("nw_it_mpotion003", oChest);
            CreateIDItem("nw_it_mpotion014", oChest);
            CreateIDItem("gauntletsofdexte", oChest);     // Gauntlets of Dex +6
            break;

        case 2: // Cirith Ungol
            // Mordor Orc Snaker (4) vs Mordor Slaughterer (3)
            CreateIDItem("nw_it_mpotion015", oChest);
            CreateIDItem("nw_it_mpotion003", oChest);
            if (Random(2) == 0)
                CreateIDItem("mordoraxe", oChest);
            break;

        case 3: // Carn Dum
            // Black Numenorean Militia (6)
            CreateIDItem("nw_it_mpotion009", oChest);
            CreateIDItem("nw_it_mpotion013", oChest);
            break;
    }
}

// --- stock the chest once per server reset ---
void StockDonationsChest()
{
    object oMod = GetModule();
    if (GetLocalInt(oMod, "DONATIONS_STOCKED")) return;
    SetLocalInt(oMod, "DONATIONS_STOCKED", 1);

    object oChest = GetObjectByTag("x2_easy_Chest2ff");
    if (!GetIsObjectValid(oChest)) return;

    // Random good-side city: 0=Gondor 1=Helms Deep 2=Rivendell 3=Lothlorien 4=Edoras
    SpawnGoodCityLoot(oChest, Random(5));
    // Random evil-side city: 0=Black Gate 1=Isengard 2=Cirith Ungol 3=Carn Dum
    SpawnEvilCityLoot(oChest, Random(4));

    // Two distinct bonus items from the full 200k-500k custom item pool
    int nPoolSize = 147;
    int nPick1 = Random(nPoolSize);
    int nPick2 = Random(nPoolSize - 1);
    if (nPick2 >= nPick1) nPick2++;     // guarantee nPick2 != nPick1

    string sItem1 = GetBonusItemResref(nPick1);
    string sItem2 = GetBonusItemResref(nPick2);
    if (sItem1 != "") CreateIDItem(sItem1, oChest);
    if (sItem2 != "") CreateIDItem(sItem2, oChest);
}

void main()
{
    object oPC = GetEnteringObject();

    // Starter XP + welcome message for brand-new characters
    if (!GetIsDM(oPC) && GetXP(oPC) == 0)
    {
        GiveXPToCreature(oPC, 3000);
        SendMessageToPC(oPC, "Welcome to Homer's Legendary Lord of the Rings!");
        SendMessageToPC(oPC, "The light of Eru smiles upon you, new adventurer. "
            + "You have been granted 3000 experience points to begin your journey. "
            + "Check the Donations Chest near the Well Mart — it may hold something "
            + "useful to help you on your way. Good luck, and may your path through "
            + "Middle-earth be legendary!");
    }

    StockDonationsChest();
}
