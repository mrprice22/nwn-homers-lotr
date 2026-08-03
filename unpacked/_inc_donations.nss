// _inc_donations.nss
// Donations Chest data: bonus item pool, stack sizes, and illicit quarantine list.
// AUTO-MANAGED by bin/sync_donations.py - do not hand-edit the generated sections.

// Number of items in the bonus pool (cases 0..BONUS_POOL_SIZE-1).
const int BONUS_POOL_SIZE = 198;

// Returns 99 for ammunition items, 1 for everything else.
int GetBonusItemStackSize(int n)
{
    switch (n)
    {
        case 3: // greaterfirearrow
        case 15: // 043
        case 16: // 044
        case 45: // elitebolt
        case 58: // wammar051
        case 68: // wammar050
        case 108: // infernoarrows009
        case 112: // deathdealer
        case 118: // arrowoftheargent
        case 140: // 045
        case 150: // slowdeath
        case 162: // boltofdrider
            return 99;
    }
    return 1;
}

string GetBonusItemResref(int n)
{
    switch (n)
    {
        case 0:    return "gwathdorhelme002";         // Gwathdor Helmet
        case 1:    return "orcsmasherflail";          // Orc Smasher Flail
        case 2:    return "beltoftherang001";         // Belt of the Rohirrin Ranger
        case 3:    return "greaterfirearrow";         // Greater Fire Arrows
        case 4:    return "gondorianhelm";            // Gondorian Helm
        case 5:    return "armhe009";                 // Shadows' Hood
        case 6:    return "shroudoffog";              // Shroud of Fog
        case 7:    return "halberd005";               // Halberd of the Rohir
        case 8:    return "gondorianrobes";           // Gondorian Robes
        case 9:    return "138";                      // Cloak of Dol Guldur
        case 10:   return "dragonsbreath4";           // Dragon's Breath +4
        case 11:   return "013";                      // Armor of The Defender
        case 12:   return "bootsofquicke002";         // Boots of Quickening
        case 13:   return "100";                      // Cover of Darkness
        case 14:   return "deadlycaress";             // Deadly Caress
        case 15:   return "043";                      // Arrow of the Orc Defender
        case 16:   return "044";                      // Arrow of the Orc Defender
        case 17:   return "staffoftheistari";         // Staff of the Istari
        case 18:   return "027";                      // Belt of the Dancer
        case 19:   return "139";                      // Ring of the Black Rider
        case 20:   return "item088";                  // Glove of the Hobbits
        case 21:   return "shieldofthegreyw";         // Shield of the Grey Walker
        case 22:   return "049";                      // Boots of the Orc Defender
        case 23:   return "039";                      // Ring of Speed and Magic Defenses
        case 24:   return "005";                      // Shell
        case 25:   return "urukhaiwhitehand";         // Uruk Hai White Mask
        case 26:   return "glovstonehear001";         // Greater Gloves of the Stone Heart
        case 27:   return "shieldofthepr001";         // Shield of the Priest
        case 28:   return "gondorianplat001";         // Greater Gondorian Plate
        case 29:   return "daggerofthest001";         // Dagger of the Stars
        case 30:   return "gondorianlongswo";         // Gondorian Longsword
        case 31:   return "fleshoftheund003";         // Rags of an Underlord
        case 32:   return "gondorianlightar";         // Gondorian Light Armor
        case 33:   return "eyesoftheforest";          // Eyes of The Forest
        case 34:   return "wallofpain";               // Wall of Pain
        case 35:   return "ixilsspike5";              // Ixil's Spike +5
        case 36:   return "001";                      // Stave of Slaughter
        case 37:   return "ashmlw006";                // Shield of the Mage
        case 38:   return "cloakofthebard";           // Cloak of the Bard
        case 39:   return "crossbowofthedef";         // Crossbow of the Defender
        case 40:   return "072";                      // Glove of a Devoured Rogue
        case 41:   return "cloakofminastiri";         // Cloak of Minas Tirith
        case 42:   return "blackheartarmor";          // Blackheart Armor
        case 43:   return "easterlinglaunch";         // Easterling Launcher
        case 44:   return "nazgulamulet";             // Nazgul Amulet
        case 45:   return "elitebolt";                // Elite Bolt
        case 46:   return "mordororcstandar";         // Ordurin-Forged Plate
        case 47:   return "shieldofkings";            // Shield of Kings
        case 48:   return "042";                      // Belt of the Orc Defender
        case 49:   return "bowoftheprotecto";         // Bow of the Protector
        case 50:   return "bootsofquicke004";         // Soft Step
        case 51:   return "cloakofdarkness";          // Cloak of Pale Darkness
        case 52:   return "117";                      // Messenger's Robe
        case 53:   return "cloth028";                 // Leather of Shadows
        case 54:   return "rubyofpower";              // Ruby of Power
        case 55:   return "felloak";                  // Felloak
        case 56:   return "amuletofdivin003";         // Amulet of Unfaithful
        case 57:   return "bootsoftheharper";         // Boots of the Harper Scout
        case 58:   return "wammar051";                // Arwen's Arrow
        case 59:   return "031";                      // Helm's Deep Shield
        case 60:   return "forestguard";              // Forest Guard shield
        case 61:   return "bootsofquickenin";         // Boots of the Rivendell Ranger
        case 62:   return "doomstouch";               // Dooms Touch
        case 63:   return "loriengarb003";            // Lorien Garb
        case 64:   return "helmoftheriderma";         // Helm of the Elite Rohirrim Soldier
        case 65:   return "aarcl008";                 // Rohirrin Heavy Armour
        case 66:   return "gondorianstaff";           // Gondorian Staff
        case 67:   return "item021";                  // Sauron's Mesh
        case 68:   return "wammar050";                // Angmar's Piercing Arrow
        case 69:   return "shieldofthedwarv";         // Shield of the Dwarven Cleric
        case 70:   return "item034";                  // Dragon's Tear
        case 71:   return "greaterringof003";         // Greater Ring of Power
        case 72:   return "longbowofdeath";           // Longbow of Death
        case 73:   return "item111";                  // Mordor Archer Bow
        case 74:   return "bowofthegaladhri";         // Bow of the Galadhrim
        case 75:   return "ringofthedwarf";           // Ring of the Dwarf
        case 76:   return "maarcl002";                // Personal Guard Armor
        case 77:   return "item133";                  // Nature's Wrap
        case 78:   return "126";                      // Forged Boots of the Orc General
        case 79:   return "ringofjustice";            // Ring of Justice
        case 80:   return "adamantitetow001";         // Fine Dwarven Tower Shield
        case 81:   return "arangerdefender";          // A Ranger Defender
        case 82:   return "gondorianplat002";         // Gondorian Captain's Plate
        case 83:   return "shieldofthero001";         // Shield of The Fleet Elf
        case 84:   return "headsplitter002";          // Black Numenorian Slasher
        case 85:   return "helmofthehighcle";         // Helm of the High Cleric
        case 86:   return "poisontippedf002";         // Poison Tipped Fang
        case 87:   return "wingsofmirkwood";          // Wings of Mirkwood
        case 88:   return "unholysigil";              // Unholy Sigil
        case 89:   return "axeofthewarrioro";         // Axe of the Warrior Orc
        case 90:   return "greatshieldofriv";         // Great Shield of Rivendell
        case 91:   return "branchofriven001";         // Branch of Rivendell
        case 92:   return "theelfboneringof";         // The Elfbone Ring of Kiran-Hai
        case 93:   return "118";                      // Chain of the Mordor Messenger
        case 94:   return "it_mring006";              // Ring of Force Shield
        case 95:   return "greaterscarab002";         // Greater Scarab Protector
        case 96:   return "kaligunsamule001";         // The Advocet's Symbol
        case 97:   return "tearhuanch";               // Tearhuanch
        case 98:   return "129";                      // Orcen Ring
        case 99:   return "140";                      // Amulet of Morgornd
        case 100:  return "cloakofkings002";          // Cloak of Queens
        case 101:  return "bladebuckle";              // BladeBuckle
        case 102:  return "x2_it_mneck012";           // Scarab of Protection +7
        case 103:  return "wardergarb";               // Warder Garb
        case 104:  return "x2_cus_bindingso";         // Bindings of Blood
        case 105:  return "stone";                    // Stonewall
        case 106:  return "greaterringof002";         // Greater Ring of Power
        case 107:  return "gondorianplate";           // Gondorian Plate
        case 108:  return "infernoarrows009";         // Scalpel Arrow
        case 109:  return "bracersofmight";           // Bracers of the Brute
        case 110:  return "x2_it_mring024";           // Ring of Clear Thought +10
        case 111:  return "x2_ashmlw005";             // Shield of Prator
        case 112:  return "deathdealer";              // Death Dealer
        case 113:  return "girdleofmig002";           // Girdle of Might
        case 114:  return "magesrighthand";           // Mage's Right Hand
        case 115:  return "cus_casielsso001";         // Casiel's Soul
        case 116:  return "cloakoffgimli";            // Cloak of Gimli
        case 117:  return "armoroftheavatar";         // Armor of the Avatar
        case 118:  return "arrowoftheargent";         // Arrow of the Argent Defender
        case 119:  return "mordororcplate";           // Mordor Orc Plate
        case 120:  return "cus_theironsk001";         // The Iron Skeleton
        case 121:  return "sashofthewhiteha";         // Sash of the White Hand
        case 122:  return "x2_cus_thegilded";         // The Gilded Defender
        case 123:  return "x2_whip_black";            // Deathcoil
        case 124:  return "shieldofgondo001";         // Greater Shield of Gondor
        case 125:  return "x2_it_mbelt005";           // Belt of Agility +7
        case 126:  return "ashmto006";                // Bulwark of the Great White Dragon
        case 127:  return "sheildofdarkness";         // Shield of Darkness
        case 128:  return "ancientmallornst";         // Ancient Mallorn Staff
        case 129:  return "128";                      // Cloak of the Reaper
        case 130:  return "x2_c3_maarcl037";          // Storm Armor of the Earth's Children
        case 131:  return "x2_it_mneck010";           // Periapt of Wisdom +10
        case 132:  return "x2_it_mcloak003";          // Mantle of Great Stealth
        case 133:  return "x2_it_mbelt002";           // Belt of Storm Giant Strength
        case 134:  return "kaligunsamuletof";         // Hareth's Amulet of Magic Resistance
        case 135:  return "it_mneck021";              // Amulet of Wisdom +10
        case 136:  return "cloakofkings";             // Cloak of Kings
        case 137:  return "amuletofthethoug";         // Amulet of the Thought
        case 138:  return "ringoftheredwarr";         // Ring of the Red Warrior
        case 139:  return "x2_maarcl050";             // Lesser Golem Armor
        case 140:  return "045";                      // Arrow of the Orc Defender
        case 141:  return "greaterringofpow";         // Greater Ring of Power
        case 142:  return "x2_sequencer3";            // Isaac's Sequencer Robe
        case 143:  return "047";                      // Dol-Guldur Helm
        case 144:  return "shadowskin";               // Shadow Skin
        case 145:  return "amuletofdivinefa";         // Amulet of Blind Faith
        case 146:  return "amuletofdivin002";         // Amulet of Faith
        case 147:  return "luckofgods";               // Luck of Gods
        case 148:  return "ringofthegeneral";         // Ring of the General
        case 149:  return "cloakoflothlorie";         // Cloak of Lothlorien
        case 150:  return "slowdeath";                // Slow Death
        case 151:  return "wdbmax006";                // Greater Axe of the Ologai Troll
        case 152:  return "brainhew";                 // Brainhew
        case 153:  return "handsofdeath";             // Hands of Death
        case 154:  return "mcloth005";                // Robe of the White Hand
        case 155:  return "galadhrimmagicus";         // Galadhrim Wizard's Belt
        case 156:  return "staffofthemallor";         // Staff of the Mallorn
        case 157:  return "eyesofthefox";             // Eyes of the Fox
        case 158:  return "item059";                  // Saruman's Crafted Ring
        case 159:  return "greatbowofrivend";         // Great Bow of Rivendell
        case 160:  return "flamesofanor";             // Flames of Anor
        case 161:  return "mordorbowmanarmo";         // Mordor Bowman Armor
        case 162:  return "boltofdrider";             // Bolt of Dark Dispel
        case 163:  return "shimmeringneckla";         // Shimmering Necklace
        case 164:  return "orcsoldiershelm";          // Orc Soldier's Helm
        case 165:  return "theevenstar003";           // The Evenstar
        case 166:  return "azuredgebattleax";         // Azuredge Battleaxe
        case 167:  return "shieldofthema002";         // Shield of the Magic Hand
        case 168:  return "headsplitter003";          // Urukai Slayer
        case 169:  return "bootsoftheoak";            // Boots of the Oak
        case 170:  return "kissofthesuccubu";         // Kiss of the Succubus
        case 171:  return "3vorpallongsword";         // +3 Vorpal Longsword
        case 172:  return "shortswordofthea";         // Short Sword of the Assassin
        case 173:  return "touchoffear";              // Touch of Fear
        case 174:  return "sickleofthehalfm";         // Sickle of the Half Moon
        case 175:  return "blindluck";                // Blind Luck
        case 176:  return "dragonslips";              // Dragon Slippers
        case 177:  return "thebeast";                 // The Beast
        case 178:  return "thecleaver";               // The Cleaver
        case 179:  return "clubofdetonat001";         // Club of Detonation +5
        case 180:  return "robesoftheshi005";         // Robes of The Shining Fist +6
        case 181:  return "showersofice";             // Showers of Ice
        case 182:  return "item006";                  // Kiru's Defense
        case 183:  return "dwarvenbattlefie";         // Dwarven Battlefield Armor
        case 184:  return "pendantoflight";           // Pendant of Light
        case 185:  return "x2_it_mring013";           // Ring of Protection +7
        case 186:  return "drotdurtor";               // Drot'durtor
        case 187:  return "tearsofthefallen";         // Tears of the Fallen
        case 188:  return "carapaceofcha001";         // Maggot's Carapace
        case 189:  return "bootsofblending";          // Boots of Blending
        case 190:  return "nw_waxmgr004";             // Axe of the Culling
        case 191:  return "maceofthedarkpri";         // Mace of the Dark Priestess
        case 192:  return "008";                      // Boots of the Mirkwood Elf
        case 193:  return "hideofthefore";            // Hide of the Forest Spirit
        case 194:  return "lavaplate";                // Lava Plate
        case 195:  return "040";                      // Ring of the Red Warrior
        case 196:  return "goreshovel";               // Goreshovel
        case 197:  return "garbofthewhitebe";         // Garb of the White Ninja
    }
    return "";
}

// Returns TRUE if the resref was removed from the bonus pool
// because it was not legitimately obtainable by players.
int IsIllicitDonationsItem(string sResRef)
{
    if (sResRef == "spectralbrand5")   return TRUE;
    if (sResRef == "stormstar")   return TRUE;
    if (sResRef == "orcquivers")   return TRUE;
    if (sResRef == "rorammy001")   return TRUE;
    if (sResRef == "epicring")   return TRUE;
    if (sResRef == "staffoftheram5")   return TRUE;
    if (sResRef == "hindosdoom4")   return TRUE;
    if (sResRef == "mordorbowmana001")   return TRUE;
    if (sResRef == "shadowstaff")   return TRUE;
    if (sResRef == "marilithscimitar")   return TRUE;
    if (sResRef == "longswordofweath")   return TRUE;
    if (sResRef == "theeyeofmadusa")   return TRUE;
    if (sResRef == "ls_angurvadal")   return TRUE;
    if (sResRef == "060")   return TRUE;
    if (sResRef == "soulrazor")   return TRUE;
    if (sResRef == "wallofpain001")   return TRUE;
    if (sResRef == "item094")   return TRUE;
    if (sResRef == "009")   return TRUE;
    if (sResRef == "crownofweathe004")   return TRUE;
    if (sResRef == "145")   return TRUE;
    if (sResRef == "arrowofhaldir")   return TRUE;
    if (sResRef == "armhe011")   return TRUE;
    if (sResRef == "glamhkama2")   return TRUE;
    if (sResRef == "item050")   return TRUE;
    if (sResRef == "026")   return TRUE;
    if (sResRef == "gwathdorhelmet")   return TRUE;
    if (sResRef == "cursedoneshelm")   return TRUE;
    if (sResRef == "garbofthewhit001")   return TRUE;
    if (sResRef == "023")   return TRUE;
    if (sResRef == "thedrowassassin")   return TRUE;
    if (sResRef == "weathertoparrow")   return TRUE;
    if (sResRef == "beltofdivinem001")   return TRUE;
    if (sResRef == "helmoftheride004")   return TRUE;
    if (sResRef == "shieldofthero003")   return TRUE;
    if (sResRef == "meshoferynlas002")   return TRUE;
    if (sResRef == "wswmls003")   return TRUE;
    if (sResRef == "item001")   return TRUE;
    if (sResRef == "arrowofthranduil")   return TRUE;
    if (sResRef == "runehammer5")   return TRUE;
    if (sResRef == "fistoftheninja")   return TRUE;
    if (sResRef == "warhammerofth001")   return TRUE;
    if (sResRef == "ringofdangersens")   return TRUE;
    if (sResRef == "wammar048")   return TRUE;
    return FALSE;
}
