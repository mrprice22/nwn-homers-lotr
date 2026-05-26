// ****************************************************************
//
// @project Moo Filter 1.3
// @author Sean Darrenkamp
// @date 5/7/2004
// @file sd_fsettings_inc
// Copyright 2004 Sean Darrenkamp
//
// This is the main code for the filter. It scans items and
// checks them for invalid or unwanted properties. The filter
// signature method at the end of the listing is where new
// properties can be put in place that the code doesn't detect.
// Think of it like adding signatures to your virus scanner. :)
// Only thing is you have to add em by hand. So some scripting
// knowledge is required.
//
// Remember, this only does items not the actual character short of
// equiped items. My thinking was that scripts are too bloated with
// both character and item scanning and they get overloaded easly.
// Hopefully this will help solve some of the problems.
//
// This code is licensed under the GPL for use. See the GNU.org
// site for more information.
//
// http://www.gnu.org/licenses/gpl.html
//
// ****************************************************************

// ****************************************************************
//
// Special thanks goes out to Tonia Stalker for helping test this.
//
// ****************************************************************

// ****************************************************************
// ****************************************************************
//
//    DON'T TOUCH ANYTHING HERE UNLESS YOU KNOW WHAT YOUR DOING!
//        (See sd_fsettings_inc for configuration options.)
//
// ****************************************************************
// ****************************************************************

#include "sd_fsettings_inc"

// Public Variables.
object oHolding;

// Function headers.
int invalidNameCheck(string sName);
int isBadFirstClass(int iClass);
int isBadSecondClass(object oPC, int iFirstClass, int iSecondClass, int iRace);
int isBadThirdClass(object oPC, int iFirstClass, int iSecondClass, int iThirdClass, int iRace);
void forceValidAppearance(object oPC, int iRace);
void filterSignature(object oItem, itemproperty prop, int ptype, int psubtype, int param1, int param1val, int costTable, int costTableValue);
void scanPropertySignatures(object oItem);
void processDamage(object oItem, itemproperty prop);
void scanDamage(object oItem);
void processEN(object oItem, itemproperty prop);
void scanEN(object oItem);
void processAB(object oItem, itemproperty prop);
void scanAB(object oItem);
void stripMisc(object oItem);
void resistPropCheck(object oItem, itemproperty prop);
void resistScanner(object oItem);
void acPropCheck(object oItem, itemproperty prop);
void acScanner(object oItem);
void stripDecrease(object oItem);
void stripOnHit(object oItem);
void stripFeats(object oItem);
void stripImmunity(object oItem);
void stripBadThrowingProperties(object oItem);
void stripBadAmmoProperties(object oItem);
void inventoryScan(object oPC);
void equipedScan(object oPC);
void itemCheck(object oItem);
void stripOverGPValue(object oItem);
void propertyLimitCheck(object oItem);
void scan(object oItem);
void inventoryScan(object oPC);
void equipedScan(object oPC);

// Scans a players gear.
// This is the main method you call from any custom script.
void scanPlayer(object oPC)
{
    if (!GetIsPC(oPC))
    {
        return;
    }

    if (GetIsDM(oPC))
    {
        return;
    }

    // Billing, hey everyone likes credit for the time they put in to their
    // work. :) Especially for all the time I took to write this.
    FloatingTextStringOnCreature("** Moo Filter 1.3 Activated **", oPC, FALSE);

    // Prep variables.
    string sName = GetName(oPC);
    int nRace = GetRacialType(oPC);
    int nSize = GetCreatureSize(oPC);
    int iClass1 = GetClassByPosition(1, oPC);
    int iClass2 = GetClassByPosition(2, oPC);
    int iClass3 = GetClassByPosition(3, oPC);
    int iClass4 = GetClassByPosition(4, oPC);

    // Basic name checking.
/*    if (invalidNameCheck(sName) == TRUE)
    {
        FloatingTextStringOnCreature("** You must have valid alpha characters, (A-Z, a-z), to start your name. **", oPC, FALSE);
        FloatingTextStringOnCreature("** Invalid name detected, booting in 30 seconds. **", oPC, FALSE);
        SetCommandable(FALSE, oPC);
        DelayCommand(30.0f, BootPC(oPC));
        return;
    }*/


    // Class checks.
/*    if (CLASS_CHECK_FLAG == TRUE)
    {
        // Check first class.
        if (isBadFirstClass(iClass1) == 1)
        {
            FloatingTextStringOnCreature("** Invalid starting class detected, booting in 30 seconds. **", oPC, FALSE);
            SetCommandable(FALSE, oPC);
            DelayCommand(30.0f, BootPC(oPC));
            return;
        }

        // Check the second and third classes if applicable.
        if (iClass2 != CLASS_TYPE_INVALID)
        {
            if (isBadSecondClass(oPC, iClass1, iClass2, nRace) == 1)
            {
                FloatingTextStringOnCreature("** Invalid second class detected, booting in 30 seconds. **", oPC, FALSE);
                SetCommandable(FALSE, oPC);
                DelayCommand(30.0f, BootPC(oPC));
                return;
            }
            if (iClass3 != CLASS_TYPE_INVALID)
            {
                if (isBadThirdClass(oPC, iClass1, iClass2, iClass3, nRace) == 1)
                {
                    FloatingTextStringOnCreature("** Invalid third class detected, booting in 30 seconds. **", oPC, FALSE);
                    SetCommandable(FALSE, oPC);
                    DelayCommand(30.0f, BootPC(oPC));
                    return;
                }
            }
        }
    }*/

    // Epic bug check.
    if(GetBaseAttackBonus(oPC)>30)
    {
        FloatingTextStringOnCreature("** Epic Level Bug Detected, booting in 60 seconds. **", oPC, FALSE);
        SetCommandable(FALSE, oPC);
        DelayCommand(60.0f, BootPC(oPC));
        return;
    }

    // Enforce normal appearances.
    if (FORCE_NORMAL_APPEARANCE == TRUE)
    {
        forceValidAppearance(oPC, nRace);
    }

    // Size category check.
    if (SIZE_CHECK == TRUE)
    {
        if (((nRace == RACIAL_TYPE_HALFLING) ||
             (nRace == RACIAL_TYPE_GNOME)) &&
             (nSize > 2))
        {
            FloatingTextStringOnCreature("** Size category vs. racial type not accepted, booting in 60 seconds. **", oPC, FALSE);
            SetCommandable(FALSE, oPC);
            DelayCommand(60.0f, BootPC(oPC));
            return;
        }
        if (((nRace == RACIAL_TYPE_HALFORC) ||
             (nRace == RACIAL_TYPE_HALFELF) ||
             (nRace == RACIAL_TYPE_ELF) ||
             (nRace == RACIAL_TYPE_DWARF) ||
             (nRace == RACIAL_TYPE_HUMAN)) &&
            (nSize > 3))
        {
            FloatingTextStringOnCreature("** Size category vs. racial type not accepted, booting in 60 seconds. **", oPC, FALSE);
            SetCommandable(FALSE, oPC);
            DelayCommand(60.0f, BootPC(oPC));
            return;
        }
    }

    equipedScan(oPC);
    DelayCommand(2.0f, inventoryScan(oPC));
    // Billing, hey everyone likes credit for the time they put in to their
    // work. :) Especially for all the time I took to write this.
    DelayCommand(4.0f, FloatingTextStringOnCreature("** Moo Filter 1.3 Scan Completed **", oPC, FALSE));
}

// Basic checks for invalid names.
// Would have been nice if bioware thought to put a regular expression function
// in the scripting language for strings.
int invalidNameCheck(string sName)
{
    if (GetStringLength(sName) < 1)
    {
        return TRUE;
    }

    string test1 = GetStringLowerCase(GetStringLeft(sName, 1));
    string test2 = GetStringLowerCase(GetStringRight(GetStringLeft(sName, 2), 1));

    if (test1 != "a" && test1 != "b" && test1 != "c" && test1 != "d" && test1 != "e" &&
        test1 != "f" && test1 != "g" && test1 != "h" && test1 != "i" && test1 != "j" &&
        test1 != "k" && test1 != "l" && test1 != "m" && test1 != "n" && test1 != "o" &&
        test1 != "p" && test1 != "q" && test1 != "r" && test1 != "s" && test1 != "t" &&
        test1 != "u" && test1 != "v" && test1 != "w" && test1 != "x" && test1 != "y" &&
        test1 != "z") // Ye flipping gods!
    {
        return FALSE;
    }
    if (test2 != "a" && test2 != "b" && test2 != "c" && test2 != "d" && test2 != "e" &&
        test2 != "f" && test2 != "g" && test2 != "h" && test2 != "i" && test2 != "j" &&
        test2 != "k" && test2 != "l" && test2 != "m" && test2 != "n" && test2 != "o" &&
        test2 != "p" && test2 != "q" && test2 != "r" && test2 != "s" && test2 != "t" &&
        test2 != "u" && test2 != "v" && test2 != "w" && test2 != "x" && test2 != "y" &&
        test2 != "z") // Ye flipping gods!
    {
        return FALSE;
    }

    return FALSE;
}

// Validates the first class a character takes.
int isBadFirstClass(int iClass)
{
    if (iClass != CLASS_TYPE_BARBARIAN &&
        iClass != CLASS_TYPE_BARD &&
        iClass != CLASS_TYPE_CLERIC &&
        iClass != CLASS_TYPE_DRUID &&
        iClass != CLASS_TYPE_FIGHTER &&
        iClass != CLASS_TYPE_MONK &&
        iClass != CLASS_TYPE_PALADIN &&
        iClass != CLASS_TYPE_RANGER &&
        iClass != CLASS_TYPE_ROGUE &&
        iClass != CLASS_TYPE_SORCERER &&
        iClass != CLASS_TYPE_WIZARD)
    {
        return 1;
    }

    return 0;
}

// Validates the second class choice based on the first.
int isBadSecondClass(object oPC, int iFirstClass, int iSecondClass, int iRace)
{
    // Arcane Archer check.
    if (iSecondClass == CLASS_TYPE_ARCANE_ARCHER)
    {
        // Race Elf or Half-Elf check.
        if (iRace != IP_CONST_RACIALTYPE_ELF &&
            iRace != IP_CONST_RACIALTYPE_HALFELF)
        {
            return 1;
        }
        // Base attach +6 check.
        if (GetBaseAttackBonus(oPC) < 6)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_WEAPON_FOCUS_LONGBOW, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SHORTBOW, oPC) == FALSE &&
            GetHasFeat(FEAT_POINT_BLANK_SHOT, oPC) == FALSE)
        {
            return 1;
        }
        // Class check
        if (iFirstClass != CLASS_TYPE_BARD &&
            iFirstClass != CLASS_TYPE_SORCERER &&
            iFirstClass != CLASS_TYPE_WIZARD)
        {
            return 1;
        }
    }

    // Assassin check.
    if (iSecondClass == CLASS_TYPE_ASSASSIN)
    {
        // Skill check.
        if (GetSkillRank(SKILL_HIDE, oPC) < 8 ||
            GetSkillRank(SKILL_MOVE_SILENTLY, oPC) < 8)
        {
            return 1;
        }
        // Alignment check not implemented for rp reasons. IE: character has a
        // change of heart for whatever reason to be good. I leave this up to
        // the DM of the server to decide.
    }

    // Blackguard Check.
    if (iSecondClass == CLASS_TYPE_BLACKGUARD)
    {
        // Skill check.
        if (GetSkillRank(SKILL_HIDE, oPC) < 5)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_CLEAVE, oPC) == FALSE)
        {
            return 1;
        }
        // Base attach +6 check.
        if (GetBaseAttackBonus(oPC) < 6)
        {
            return 1;
        }
        // Alignment check not implemented for rp reasons. IE: character has a
        // change of heart for whatever reason to be good. I leave this up to
        // the DM of the server to decide.
    }

    // Harper Scout check.
    if (iSecondClass == CLASS_TYPE_HARPER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_ALERTNESS, oPC) == FALSE ||
            GetHasFeat(FEAT_IRON_WILL, oPC) == FALSE)
        {
            return 1;
        }
        // Skill check.
        if (GetSkillRank(SKILL_DISCIPLINE, oPC) < 4 ||
            GetSkillRank(SKILL_LORE, oPC) < 6 ||
            GetSkillRank(SKILL_PERSUADE, oPC) < 8 ||
            GetSkillRank(SKILL_SEARCH, oPC) < 4)
        {
            return 1;
        }
        // Alignment check not implemented for rp reasons. IE: character has a
        // change of heart for whatever reason to be good. I leave this up to
        // the DM of the server to decide.
    }

    // Shadowdancer check.
    if (iSecondClass == CLASS_TYPE_SHADOWDANCER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_DODGE, oPC) == FALSE ||
            GetHasFeat(FEAT_MOBILITY, oPC) == FALSE)
        {
            return 1;
        }
        // Skill check.
        if (GetSkillRank(SKILL_MOVE_SILENTLY, oPC) < 8 ||
            GetSkillRank(SKILL_HIDE, oPC) < 10 ||
            GetSkillRank(SKILL_TUMBLE, oPC) < 5)
        {
            return 1;
        }
    }

    // Champion of Torm check.
    if (iSecondClass == CLASS_TYPE_DIVINE_CHAMPION ||
        iSecondClass == CLASS_TYPE_DIVINECHAMPION)
    {
        // Base attach +7 check.
        if (GetBaseAttackBonus(oPC) < 7)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_WEAPON_FOCUS_BASTARD_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_CLUB, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DAGGER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DIRE_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DOUBLE_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DWAXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HALBERD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HAND_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HEAVY_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KAMA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KATANA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KUKRI, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LONG_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_MORNING_STAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_RAPIER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCIMITAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCYTHE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SHORT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SICKLE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SPEAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_STAFF, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_TWO_BLADED_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WAR_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_UNARMED_STRIKE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WHIP, oPC) == FALSE)
        {
            return 1;
        }
    }

    // Weapon master check.
    if (iSecondClass == CLASS_TYPE_WEAPON_MASTER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_WEAPON_FOCUS_BASTARD_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_CLUB, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DAGGER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DIRE_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DOUBLE_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DWAXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HALBERD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HAND_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HEAVY_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KAMA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KATANA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KUKRI, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LONG_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_MORNING_STAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_RAPIER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCIMITAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCYTHE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SHORT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SICKLE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SPEAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_STAFF, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_TWO_BLADED_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WAR_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_UNARMED_STRIKE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WHIP, oPC) == FALSE)
        {
            return 1;
        }
        if (GetHasFeat(FEAT_DODGE, oPC) == FALSE ||
            GetHasFeat(FEAT_EXPERTISE, oPC) == FALSE ||
            GetHasFeat(FEAT_MOBILITY, oPC) == FALSE ||
            GetHasFeat(FEAT_SPRING_ATTACK, oPC) == FALSE ||
            GetHasFeat(FEAT_WHIRLWIND_ATTACK, oPC) == FALSE)
        {
            return 1;
        }
        // Skill check.
        if (GetSkillRank(SKILL_INTIMIDATE, oPC) < 4)
        {
            return 1;
        }
    }

    // Shifter check.
    if (iSecondClass == CLASS_TYPE_SHIFTER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_ALERTNESS, oPC) == FALSE ||
            GetHasFeat(FEAT_WILD_SHAPE, oPC) == FALSE)
        {
            return 1;
        }
        // Here we check to make sure there's atleast 3 spell caster levels.
        // Since the druid is the only class with a natural wild shape ability
        // we check that.
        if (iFirstClass != CLASS_TYPE_DRUID &&
            GetLevelByClass(CLASS_TYPE_DRUID, oPC) < 3)
        {
            return 1;
        }
    }

    // Palemaster check.
    if (iSecondClass == CLASS_TYPE_PALE_MASTER ||
        iSecondClass == CLASS_TYPE_PALEMASTER)
    {
        // Class check.
        if (GetLevelByClass(CLASS_TYPE_BARD, oPC) < 3 &&
            GetLevelByClass(CLASS_TYPE_SORCERER, oPC) < 3 &&
            GetLevelByClass(CLASS_TYPE_WIZARD, oPC) < 3)
        {
            return 1;
        }
    }

    // Red Dragon Disciple
    if (iSecondClass == CLASS_TYPE_DRAGON_DISCIPLE ||
        iSecondClass == CLASS_TYPE_DRAGONDISCIPLE)
    {
        // Skill check.
        if (GetSkillRank(SKILL_LORE, oPC) < 8)
        {
            return 1;
        }
        // Class check.
        if (iFirstClass != CLASS_TYPE_BARD &&
            iFirstClass != CLASS_TYPE_SORCERER)
        {
            return 1;
        }
    }

    // Dwarven defender check.
    if (iSecondClass == CLASS_TYPE_DWARVEN_DEFENDER ||
        iSecondClass == CLASS_TYPE_DWARVENDEFENDER)
    {
        // Base attach +7 check.
        if (GetBaseAttackBonus(oPC) < 7)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_DODGE, oPC) == FALSE ||
            GetHasFeat(FEAT_TOUGHNESS, oPC) == FALSE)
        {
            return 1;
        }
        // Race check.
        if (GetRacialType(oPC) != RACIAL_TYPE_DWARF)
        {
            return 1;
        }
        else
        {
            // Enforce my pet pieve about people not being dwarves
            // when dwarven defenders. They're lucky I don't smite them if they
            // choose elven appearances. Yes I'm raciest about this, DEAL! :D
            if (GetAppearanceType(oPC) != APPEARANCE_TYPE_DWARF)
            {
                FloatingTextStringOnCreature("** By Moradin's hammer! Are ye not proud of yer dwarven herritage!?? **", oPC, FALSE);
                SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_DWARF);
                FloatingTextStringOnCreature("** Be proud yer one of the stout folk! **", oPC, FALSE);
            }
        }
    }

    return 0;
}

// Validated the third class choice.
int isBadThirdClass(object oPC, int iFirstClass, int iSecondClass, int iThirdClass, int iRace)
{
    // Arcane Archer check.
    if (iThirdClass == CLASS_TYPE_ARCANE_ARCHER)
    {
        // Race Elf or Half-Elf check.
        if (iRace != IP_CONST_RACIALTYPE_ELF &&
            iRace != IP_CONST_RACIALTYPE_HALFELF)
        {
            return 1;
        }
        // Base attach +6 check.
        if (GetBaseAttackBonus(oPC) < 6)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_WEAPON_FOCUS_LONGBOW, oPC) == FALSE ||
            GetHasFeat(FEAT_WEAPON_FOCUS_SHORTBOW, oPC) == FALSE ||
            GetHasFeat(FEAT_POINT_BLANK_SHOT, oPC) == FALSE)
        {
            return 1;
        }
        // Class check
        if (iFirstClass != CLASS_TYPE_BARD &&
            iFirstClass != CLASS_TYPE_SORCERER &&
            iFirstClass != CLASS_TYPE_WIZARD &&
            iSecondClass != CLASS_TYPE_BARD &&
            iSecondClass != CLASS_TYPE_SORCERER &&
            iSecondClass != CLASS_TYPE_WIZARD)
        {
            return 1;
        }
    }

    // Assassin check.
    if (iThirdClass == CLASS_TYPE_ASSASSIN)
    {
        // Skill check.
        if (GetSkillRank(SKILL_HIDE, oPC) < 8 ||
            GetSkillRank(SKILL_MOVE_SILENTLY, oPC) < 8)
        {
            return 1;
        }
        // Alignment check not implemented for rp reasons. IE: character has a
        // change of heart for whatever reason to be good. I leave this up to
        // the DM of the server to decide.
    }

    // Blackguard Check.
    if (iThirdClass == CLASS_TYPE_BLACKGUARD)
    {
        // Skill check.
        if (GetSkillRank(SKILL_HIDE, oPC) < 5)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_CLEAVE, oPC) == FALSE)
        {
            return 1;
        }
        // Base attach +6 check.
        if (GetBaseAttackBonus(oPC) < 6)
        {
            return 1;
        }
        // Alignment check not implemented for rp reasons. IE: character has a
        // change of heart for whatever reason to be good. I leave this up to
        // the DM of the server to decide.
    }

    // Harper Scout check.
    if (iThirdClass == CLASS_TYPE_HARPER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_ALERTNESS, oPC) == FALSE ||
            GetHasFeat(FEAT_IRON_WILL, oPC) == FALSE)
        {
            return 1;
        }
        // Skill check.
        if (GetSkillRank(SKILL_DISCIPLINE, oPC) < 4 ||
            GetSkillRank(SKILL_LORE, oPC) < 6 ||
            GetSkillRank(SKILL_PERSUADE, oPC) < 8 ||
            GetSkillRank(SKILL_SEARCH, oPC) < 4)
        {
            return 1;
        }
        // Alignment check not implemented for rp reasons. IE: character has a
        // change of heart for whatever reason to be good. I leave this up to
        // the DM of the server to decide.
    }

    // Shadowdancer check.
    if (iThirdClass == CLASS_TYPE_SHADOWDANCER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_DODGE, oPC) == FALSE ||
            GetHasFeat(FEAT_MOBILITY, oPC) == FALSE)
        {
            return 1;
        }
        // Skill check.
        if (GetSkillRank(SKILL_MOVE_SILENTLY, oPC) < 8 ||
            GetSkillRank(SKILL_HIDE, oPC) < 10 ||
            GetSkillRank(SKILL_TUMBLE, oPC) < 5)
        {
            return 1;
        }
    }

    // Champion of Torm check.
    if (iThirdClass == CLASS_TYPE_DIVINE_CHAMPION ||
        iThirdClass == CLASS_TYPE_DIVINECHAMPION)
    {
        // Base attach +7 check.
        if (GetBaseAttackBonus(oPC) < 7)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_WEAPON_FOCUS_BASTARD_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_CLUB, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DAGGER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DIRE_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DOUBLE_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DWAXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HALBERD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HAND_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HEAVY_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KAMA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KATANA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KUKRI, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LONG_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_MORNING_STAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_RAPIER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCIMITAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCYTHE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SHORT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SICKLE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SPEAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_STAFF, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_TWO_BLADED_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WAR_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_UNARMED_STRIKE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WHIP, oPC) == FALSE)
        {
            return 1;
        }
    }

    // Weapon master check.
    if (iThirdClass == CLASS_TYPE_WEAPON_MASTER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_WEAPON_FOCUS_BASTARD_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_CLUB, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DAGGER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DIRE_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DOUBLE_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_DWAXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_GREAT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HALBERD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HAND_AXE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_HEAVY_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KAMA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KATANA, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_KUKRI, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_FLAIL, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LIGHT_MACE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_LONG_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_MORNING_STAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_RAPIER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCIMITAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SCYTHE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SHORT_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SICKLE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_SPEAR, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_STAFF, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_TWO_BLADED_SWORD, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WAR_HAMMER, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_UNARMED_STRIKE, oPC) == FALSE &&
            GetHasFeat(FEAT_WEAPON_FOCUS_WHIP, oPC) == FALSE)
        {
            return 1;
        }
        if (GetHasFeat(FEAT_DODGE, oPC) == FALSE ||
            GetHasFeat(FEAT_EXPERTISE, oPC) == FALSE ||
            GetHasFeat(FEAT_MOBILITY, oPC) == FALSE ||
            GetHasFeat(FEAT_SPRING_ATTACK, oPC) == FALSE ||
            GetHasFeat(FEAT_WHIRLWIND_ATTACK, oPC) == FALSE)
        {
            return 1;
        }
        // Skill check.
        if (GetSkillRank(SKILL_INTIMIDATE, oPC) < 4)
        {
            return 1;
        }
    }

    // Shifter check.
    if (iThirdClass == CLASS_TYPE_SHIFTER)
    {
        // Feat check.
        if (GetHasFeat(FEAT_ALERTNESS, oPC) == FALSE ||
            GetHasFeat(FEAT_WILD_SHAPE, oPC) == FALSE)
        {
            return 1;
        }
        // Here we check to make sure there's atleast 3 spell caster levels.
        // Since the druid is the only class with a natural wild shape ability
        // we check that.
        if ((iFirstClass != CLASS_TYPE_DRUID &&
             iSecondClass != CLASS_TYPE_DRUID) ||
             GetLevelByClass(CLASS_TYPE_DRUID, oPC) < 3)
        {
            return 1;
        }
    }

    // Palemaster check.
    if (iThirdClass == CLASS_TYPE_PALE_MASTER ||
        iThirdClass == CLASS_TYPE_PALEMASTER)
    {
        // Class check.
        if (GetLevelByClass(CLASS_TYPE_BARD, oPC) < 3 &&
            GetLevelByClass(CLASS_TYPE_SORCERER, oPC) < 3 &&
            GetLevelByClass(CLASS_TYPE_WIZARD, oPC) < 3)
        {
            return 1;
        }
    }

    // Red Dragon Disciple
    if (iThirdClass == CLASS_TYPE_DRAGON_DISCIPLE ||
        iThirdClass == CLASS_TYPE_DRAGONDISCIPLE)
    {
        // Skill check.
        if (GetSkillRank(SKILL_LORE, oPC) < 8)
        {
            return 1;
        }
        // Class check.
        if (iFirstClass != CLASS_TYPE_BARD &&
            iFirstClass != CLASS_TYPE_SORCERER &&
            iSecondClass != CLASS_TYPE_BARD &&
            iSecondClass != CLASS_TYPE_SORCERER)
        {
            return 1;
        }
    }

    // Dwarven defender check.
    if (iThirdClass == CLASS_TYPE_DWARVEN_DEFENDER ||
        iThirdClass == CLASS_TYPE_DWARVENDEFENDER)
    {
        // Base attach +7 check.
        if (GetBaseAttackBonus(oPC) < 7)
        {
            return 1;
        }
        // Feat check.
        if (GetHasFeat(FEAT_DODGE, oPC) == FALSE ||
            GetHasFeat(FEAT_TOUGHNESS, oPC) == FALSE)
        {
            return 1;
        }
        // Race check.
        if (GetRacialType(oPC) != RACIAL_TYPE_DWARF)
        {
            return 1;
        }
        else
        {
            // Enforce my pet pieve about people not being dwarves
            // when dwarven defenders. They're lucky I don't smite them if they
            // choose elven appearances. Yes I'm raciest about this, DEAL! :D
            if (GetAppearanceType(oPC) != APPEARANCE_TYPE_DWARF)
            {
                FloatingTextStringOnCreature("** By Moradin's hammer! Are ye not proud of yer dwarven herritage!?? **", oPC, FALSE);
                SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_DWARF);
                FloatingTextStringOnCreature("** Be proud yer one of the stout folk! **", oPC, FALSE);
            }
        }
    }

    return 0;
}

// Enforces a valid player appearance. Great for nerfing some nulls.
void forceValidAppearance(object oPC, int iRace)
{
    if (iRace == IP_CONST_RACIALTYPE_DWARF)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_DWARF);
    }
    else if (iRace == IP_CONST_RACIALTYPE_ELF)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_ELF);
    }
    else if (iRace == IP_CONST_RACIALTYPE_GNOME)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_GNOME);
    }
    else if (iRace == IP_CONST_RACIALTYPE_HALFELF)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_HALF_ELF);
    }
    else if (iRace == IP_CONST_RACIALTYPE_HALFLING)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_HALFLING);
    }
    else if (iRace == IP_CONST_RACIALTYPE_HALFORC)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_HALF_ORC);
    }
    else if (iRace == IP_CONST_RACIALTYPE_HUMAN)
    {
        SetCreatureAppearanceType(oPC, APPEARANCE_TYPE_HUMAN);
    }
}

// Scan equipped gear.
void equipedScan(object oPC)
{
    int c = 0;

    // Whack creature equips.
    DestroyObject(GetItemInSlot(INVENTORY_SLOT_CARMOUR, oPC));
    DestroyObject(GetItemInSlot(INVENTORY_SLOT_CWEAPON_B, oPC));
    DestroyObject(GetItemInSlot(INVENTORY_SLOT_CWEAPON_L, oPC));
    DestroyObject(GetItemInSlot(INVENTORY_SLOT_CWEAPON_R, oPC));

    // 0-13 are normal equipment slots.
    for (c = 0; c < 14; c++)
    {
        object oItem = GetItemInSlot(c, oPC);

        SetIdentified(oItem, TRUE);
        AssignCommand(oPC, ActionUnequipItem(oItem));
        AssignCommand(oPC, ActionEquipItem(oItem, c));
        scan(oItem);
    }
}

// Scan inventory.
void inventoryScan(object oPC)
{
    object oItem = GetFirstItemInInventory(oPC);

    while (GetIsObjectValid(oItem))
    {
        SetPlotFlag(oItem, FALSE);
        SetDroppableFlag(oItem, TRUE);
        SetIdentified(oItem, TRUE);
        DelayCommand(0.06f, scan(oItem));
        oItem = GetNextItemInInventory(oPC);
    }
}

// Scan an item for duplicate properties and remove them.
void scan(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);
    int count = 0;

    while (GetIsItemPropertyValid(prop))
    {
        string ptype = IntToString(GetItemPropertyType(prop));

        // Nab everything but bonus spell slots.
        if (StringToInt(ptype) != ITEM_PROPERTY_BONUS_SPELL_SLOT_OF_LEVEL_N)
        {
            string psubtype = IntToString(GetItemPropertySubType(prop));
            string param1 = IntToString(GetItemPropertyParam1(prop));
            string param1val = IntToString(GetItemPropertyParam1Value(prop));
            string costTable = IntToString(GetItemPropertyCostTable(prop));
            // Value eliminated due to boot AC bonus stack bug.
            //string costTableValue = IntToString(GetItemPropertyCostTableValue(prop));
            //string propHash = ptype + psubtype + param1 + param1val + costTable + costTableValue;
            string propHash = ptype + psubtype + param1 + param1val + costTable;
            int flag = GetLocalInt(oItem, propHash);

            if (flag == 1)
            {
                RemoveItemProperty(oItem, prop);
            }
            else
            {
                SetLocalInt(oItem, propHash, 1);
                DelayCommand(15.0f, DeleteLocalInt(oItem, propHash));
                SetLocalString(oItem, "PROP_" + IntToString(count), propHash);
                count = count + 1;
            }
        }

        prop = GetNextItemProperty(oItem);
    }

    DelayCommand(0.05f, SetLocalInt(oItem, "FLAG_COUNT", count));
    DelayCommand(15.0f, DeleteLocalInt(oItem, "FLAG_COUNT"));
    DelayCommand(0.05f, propertyLimitCheck(oItem));
}

// This part enforces the property max limit.
void propertyLimitCheck(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);
    int counter = 1;

    while (GetIsItemPropertyValid(prop))
    {
        prop = GetNextItemProperty(oItem);
        counter++;
        if (counter > MAX_PROPERTIES)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    DelayCommand(0.05f, stripOverGPValue(oItem));
}

// Enforce a set GP value per item.
void stripOverGPValue(object oItem)
{
    if (GP_VALUE_CHECK == TRUE && GetGoldPieceValue(oItem) > MAX_GOLD)
    {
        DestroyObject(oItem, 0.0f);
        return;
    }
    else
    {
        DelayCommand(0.05f, itemCheck(oItem));
    }
}

// Scans an object based on item type.
void itemCheck(object oItem)
{
    // Make sure we have something valid to scan
    if (GetIsObjectValid(oItem) == FALSE)
    {
       DestroyObject(oItem, 0.0f);
       return;
    }

    // If it's a container, whack it.
    if (GetHasInventory(oItem))
    {
        DestroyObject(oItem);
        return;
    }
    else if (GetBaseItemType(oItem) == BASE_ITEM_ARROW ||
             GetBaseItemType(oItem) == BASE_ITEM_BOLT ||
             GetBaseItemType(oItem) == BASE_ITEM_BULLET)
    {
       stripBadAmmoProperties(oItem);
    }
    else if (GetBaseItemType(oItem) == BASE_ITEM_DART ||
             GetBaseItemType(oItem) == BASE_ITEM_SHURIKEN ||
             GetBaseItemType(oItem) == BASE_ITEM_THROWINGAXE)
    {
       stripBadThrowingProperties(oItem);
    }
    else if ((GetBaseItemType(oItem) == BASE_ITEM_THIEVESTOOLS && ALLOW_THIEVESTOOLS == FALSE) ||
             (GetBaseItemType(oItem) == BASE_ITEM_TORCH && ALLOW_TORCHES == FALSE) ||
             (GetBaseItemType(oItem) == BASE_ITEM_POTIONS && ALLOW_POTIONS == FALSE) ||
             (GetBaseItemType(oItem) == BASE_ITEM_SCROLL && ALLOW_SCROLLS == FALSE))
    {
        DestroyObject(oItem);
        return;
    }
    else
    {
        // Otherwise scan it.
        stripImmunity(oItem);
    }
}

// Eliminates bad ammo properties.
void stripBadAmmoProperties(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    if (GetItemStackSize(oItem) > 99)
    {
        SetItemStackSize(oItem, 99);
    }

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_AC_BONUS ||
            type == ITEM_PROPERTY_AC_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_AC_BONUS_VS_DAMAGE_TYPE ||
            type == ITEM_PROPERTY_AC_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_AC_BONUS_VS_SPECIFIC_ALIGNMENT ||
            type == ITEM_PROPERTY_ATTACK_BONUS ||
            type == ITEM_PROPERTY_ATTACK_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_ATTACK_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_ATTACK_BONUS_VS_SPECIFIC_ALIGNMENT ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_SPECIFIC_ALIGNEMENT ||
            type == ITEM_PROPERTY_ABILITY_BONUS ||
            type == ITEM_PROPERTY_BONUS_FEAT ||
            type == ITEM_PROPERTY_ARCANE_SPELL_FAILURE ||
            type == ITEM_PROPERTY_BONUS_SPELL_SLOT_OF_LEVEL_N ||
            type == ITEM_PROPERTY_DARKVISION ||
            type == ITEM_PROPERTY_DAMAGE_RESISTANCE ||
            type == ITEM_PROPERTY_KEEN ||
            type == ITEM_PROPERTY_HASTE ||
            type == ITEM_PROPERTY_HOLY_AVENGER ||
            type == ITEM_PROPERTY_IMPROVED_EVASION ||
            type == ITEM_PROPERTY_FREEDOM_OF_MOVEMENT ||
            type == ITEM_PROPERTY_MIGHTY ||
            type == ITEM_PROPERTY_MIND_BLANK ||
            type == ITEM_PROPERTY_TRUE_SEEING)
        {
            RemoveItemProperty(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    stripImmunity(oItem);
}

// Takes care of bad throwing item properties.
void stripBadThrowingProperties(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    if (GetItemStackSize(oItem) > 50)
    {
        SetItemStackSize(oItem, 50);
    }

    // Left in for possible future use.
    /*while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_REPLACE_ME)
        {
            RemoveItemProperty(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }*/
    stripImmunity(oItem);
}

// Strips off immunities from an item.
void stripImmunity(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_IMMUNITY_DAMAGE_TYPE ||
            type == ITEM_PROPERTY_IMMUNITY_MISCELLANEOUS ||
            type == ITEM_PROPERTY_IMMUNITY_SPECIFIC_SPELL ||
            type == ITEM_PROPERTY_IMMUNITY_SPELL_SCHOOL ||
            type == ITEM_PROPERTY_IMMUNITY_SPELLS_BY_LEVEL)
        {
            RemoveItemProperty(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    stripFeats(oItem);
}

// Strips away bonus feats.
void stripFeats(object oItem)
{
    if (STRIP_FEATS == TRUE)
    {
        itemproperty prop = GetFirstItemProperty(oItem);

        while (GetIsItemPropertyValid(prop))
        {
            int type = GetItemPropertyType(prop);

            if (type == ITEM_PROPERTY_BONUS_FEAT)
            {
                RemoveItemProperty(oItem, prop);
            }

            prop = GetNextItemProperty(oItem);
        }
    }
    stripOnHit(oItem);
}

// Strips away on hits.
void stripOnHit(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if ((type == ITEM_PROPERTY_ON_HIT_PROPERTIES && ON_HIT_STRIP) ||
            type == ITEM_PROPERTY_ON_MONSTER_HIT ||
            type == ITEM_PROPERTY_ONHITCASTSPELL)
        {
            RemoveItemProperty(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    stripDecrease(oItem);
}

// Strips of decreased items. No negative ability bugs.
void stripDecrease(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_DAMAGE_VULNERABILITY ||
            type == ITEM_PROPERTY_DECREASED_ABILITY_SCORE ||
            type == ITEM_PROPERTY_DECREASED_AC ||
            type == ITEM_PROPERTY_DECREASED_ATTACK_MODIFIER ||
            type == ITEM_PROPERTY_DECREASED_DAMAGE ||
            type == ITEM_PROPERTY_DECREASED_ENHANCEMENT_MODIFIER ||
            type == ITEM_PROPERTY_DECREASED_SAVING_THROWS ||
            type == ITEM_PROPERTY_DECREASED_SAVING_THROWS_SPECIFIC ||
            type == ITEM_PROPERTY_DECREASED_SKILL_MODIFIER ||
            type == ITEM_PROPERTY_NO_DAMAGE)
        {
            RemoveItemProperty(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    acScanner(oItem);
}

// Scans for AC properties and passes ac items to acPropCheck
void acScanner(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_AC_BONUS ||
            type == ITEM_PROPERTY_AC_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_AC_BONUS_VS_DAMAGE_TYPE ||
            type == ITEM_PROPERTY_AC_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_AC_BONUS_VS_SPECIFIC_ALIGNMENT)
        {
            acPropCheck(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    resistScanner(oItem);
}

// Checks to enforce the MAX_AC limit.
void acPropCheck(object oItem, itemproperty prop)
{
    int ptype = GetItemPropertyType(prop);
    int costTableValue = GetItemPropertyCostTableValue(prop);
    int psubtype = GetItemPropertySubType(prop);

    if (costTableValue > MAX_AC)
    {
        RemoveItemProperty(oItem, prop);
        if (MAX_AC < 1)
        {
           return;
        }

        if (ptype == ITEM_PROPERTY_AC_BONUS)
        {
            AddItemProperty(DURATION_TYPE_PERMANENT, ItemPropertyACBonus(MAX_AC), oItem, 0.0f);
        }
        else if (ptype == ITEM_PROPERTY_AC_BONUS_VS_ALIGNMENT_GROUP)
        {
            if (NONE_STRIP && psubtype == 0)
            {
                return;
            }
            AddItemProperty(DURATION_TYPE_PERMANENT, ItemPropertyACBonusVsAlign(psubtype, MAX_AC), oItem, 0.0f);
        }
        else if (ptype == ITEM_PROPERTY_AC_BONUS_VS_DAMAGE_TYPE)
        {
            AddItemProperty(DURATION_TYPE_PERMANENT, ItemPropertyACBonusVsDmgType(psubtype, MAX_AC), oItem, 0.0f);
        }
        else if (ptype == ITEM_PROPERTY_AC_BONUS_VS_RACIAL_GROUP)
        {
            AddItemProperty(DURATION_TYPE_PERMANENT, ItemPropertyACBonusVsRace(psubtype, MAX_AC), oItem, 0.0f);
        }
        else if (ptype == ITEM_PROPERTY_AC_BONUS_VS_SPECIFIC_ALIGNMENT)
        {
            AddItemProperty(DURATION_TYPE_PERMANENT, ItemPropertyACBonusVsSAlign(psubtype, MAX_AC), oItem, 0.0f);
        }
    }
}

// Scans for AC properties and passes ac items to acPropCheck
void resistScanner(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_DAMAGE_RESISTANCE)
        {
            resistPropCheck(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    stripMisc(oItem);
}

// Check to enforce resistance policy on server.
void resistPropCheck(object oItem, itemproperty prop)
{
    int psubtype = GetItemPropertySubType(prop);
    int costTableValue = GetItemPropertyCostTableValue(prop);

    if (costTableValue > MAX_RESIST)
    {
        RemoveItemProperty(oItem, prop);
        if (REMOVE_DEVINE_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_DIVINE)
        {
            return;
        }
        if (REMOVE_MAGIC_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_MAGICAL)
        {
            return;
        }
        if (REMOVE_NEGATIVE_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_NEGATIVE)
        {
            return;
        }
        if (REMOVE_POSITIVE_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_POSITIVE)
        {
            return;
        }
        itemproperty ip = ItemPropertyDamageResistance(psubtype, MAX_RESIST);
        AddItemProperty(DURATION_TYPE_PERMANENT, ip, oItem, 0.0f);
    }
    else // Ok, we didn't go over the limit. Check for banned resist types anyway.
    {
        if (REMOVE_DEVINE_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_DIVINE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_MAGIC_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_MAGICAL)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_NEGATIVE_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_NEGATIVE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_POSITIVE_RESIST == TRUE && psubtype == IP_CONST_DAMAGETYPE_POSITIVE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
    }
}

// Strips away misc.
void stripMisc(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);
    int baseType = GetBaseItemType(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_MONSTER_DAMAGE ||
            type == ITEM_PROPERTY_ON_MONSTER_HIT ||
            type == ITEM_PROPERTY_REGENERATION ||
            type == ITEM_PROPERTY_REGENERATION_VAMPIRIC ||
            type == ITEM_PROPERTY_DAMAGE_REDUCTION)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (type == ITEM_PROPERTY_CAST_SPELL && ALLOW_CAST_ITEMS == FALSE)
        {
           if (baseType == BASE_ITEM_POTIONS && ALLOW_POTIONS == TRUE)
           {
               // Do nothing since we are allowing potions.
           }
           else if (baseType == BASE_ITEM_SCROLL && ALLOW_SCROLLS == TRUE)
           {
               // Do nothing since we are allowing scrolls.
           }
           else
           {
               RemoveItemProperty(oItem, prop);
           }
        }

        prop = GetNextItemProperty(oItem);
    }
    scanAB(oItem);
}

// Scan attack bonus properties.
void scanAB(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_ATTACK_BONUS ||
            type == ITEM_PROPERTY_ATTACK_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_ATTACK_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_ATTACK_BONUS_VS_SPECIFIC_ALIGNMENT)
        {
            processAB(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    scanEN(oItem);
}

// Process attack bonus properties.
void processAB(object oItem, itemproperty prop)
{
    int ptype = GetItemPropertyType(prop);
    int psubtype = GetItemPropertySubType(prop);
    int costTableValue = GetItemPropertyCostTableValue(prop);
    itemproperty ip;

    if (costTableValue > MAX_AB_ITEM)
    {
        RemoveItemProperty(oItem, prop);
        if (ptype == ITEM_PROPERTY_ATTACK_BONUS)
        {
            ip = ItemPropertyAttackBonus(MAX_AB_ITEM);
        }
        else if (ptype == ITEM_PROPERTY_ATTACK_BONUS_VS_ALIGNMENT_GROUP)
        {
            if (NONE_STRIP && psubtype == 0)
            {
                return;
            }
            ip = ItemPropertyAttackBonusVsAlign(psubtype, MAX_AB_ITEM);
        }
        else if (ptype == ITEM_PROPERTY_ATTACK_BONUS_VS_RACIAL_GROUP)
        {
            ip = ItemPropertyAttackBonusVsRace(psubtype, MAX_AB_ITEM);
        }
        else if (ptype == ITEM_PROPERTY_ATTACK_BONUS_VS_SPECIFIC_ALIGNMENT)
        {
            ip = ItemPropertyAttackBonusVsSAlign(psubtype, MAX_AB_ITEM);
        }
        AddItemProperty(DURATION_TYPE_PERMANENT, ip, oItem);
    }
}

// Scan enhancement bonus properties.
void scanEN(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_ENHANCEMENT_BONUS ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_SPECIFIC_ALIGNEMENT)
        {
            processEN(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    scanDamage(oItem);
}

// Process enhancement bonus properties.
void processEN(object oItem, itemproperty prop)
{
    int ptype = GetItemPropertyType(prop);
    int psubtype = GetItemPropertySubType(prop);
    int costTableValue = GetItemPropertyCostTableValue(prop);
    itemproperty ip;

    if (costTableValue > MAX_EN_ITEM)
    {
        RemoveItemProperty(oItem, prop);
        if (ptype == ITEM_PROPERTY_ENHANCEMENT_BONUS)
        {
            ip = ItemPropertyEnhancementBonus(MAX_EN_ITEM);
        }
        else if (ptype == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_ALIGNMENT_GROUP)
        {
            if (NONE_STRIP && psubtype == 0)
            {
                return;
            }
            ip = ItemPropertyEnhancementBonusVsAlign(psubtype, MAX_EN_ITEM);
        }
        else if (ptype == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_RACIAL_GROUP)
        {
            ip = ItemPropertyEnhancementBonusVsRace(psubtype, MAX_EN_ITEM);
        }
        else if (ptype == ITEM_PROPERTY_ENHANCEMENT_BONUS_VS_SPECIFIC_ALIGNEMENT)
        {
            ip = ItemPropertyEnhancementBonusVsSAlign(psubtype, MAX_EN_ITEM);
        }
        AddItemProperty(DURATION_TYPE_PERMANENT, ip, oItem);
    }
}

// Scan for damage bonus properties.
void scanDamage(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int type = GetItemPropertyType(prop);

        if (type == ITEM_PROPERTY_DAMAGE_BONUS ||
            type == ITEM_PROPERTY_DAMAGE_BONUS_VS_ALIGNMENT_GROUP ||
            type == ITEM_PROPERTY_DAMAGE_BONUS_VS_RACIAL_GROUP ||
            type == ITEM_PROPERTY_DAMAGE_BONUS_VS_SPECIFIC_ALIGNMENT)
        {
            processDamage(oItem, prop);
        }

        prop = GetNextItemProperty(oItem);
    }
    scanPropertySignatures(oItem);
}

// Process damage bonus properties.
void processDamage(object oItem, itemproperty prop)
{
    int ptype = GetItemPropertyType(prop);
    int psubtype = GetItemPropertySubType(prop);
    int param1val = GetItemPropertyParam1Value(prop);
    int costTableValue = GetItemPropertyCostTableValue(prop);
    itemproperty ip;

    if (ptype == ITEM_PROPERTY_DAMAGE_BONUS_VS_ALIGNMENT_GROUP)
    {
        if (NONE_STRIP && psubtype == 0)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_DEVINE_DAMAGE == TRUE && param1val == IP_CONST_DAMAGETYPE_DIVINE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_MAGIC_DAMAGE == TRUE && param1val == IP_CONST_DAMAGETYPE_MAGICAL)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_NEGATIVE_DAMAGE == TRUE && param1val == IP_CONST_DAMAGETYPE_NEGATIVE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_POSITIVE_DAMAGE == TRUE && param1val == IP_CONST_DAMAGETYPE_POSITIVE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
    }
    else
    {
        if (REMOVE_DEVINE_DAMAGE == TRUE && psubtype == IP_CONST_DAMAGETYPE_DIVINE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_MAGIC_DAMAGE == TRUE && psubtype == IP_CONST_DAMAGETYPE_MAGICAL)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_NEGATIVE_DAMAGE == TRUE && psubtype == IP_CONST_DAMAGETYPE_NEGATIVE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
        if (REMOVE_POSITIVE_DAMAGE == TRUE && psubtype == IP_CONST_DAMAGETYPE_POSITIVE)
        {
            RemoveItemProperty(oItem, prop);
            return;
        }
    }
}

// Scanner to get property signatures.
void scanPropertySignatures(object oItem)
{
    itemproperty prop = GetFirstItemProperty(oItem);

    while (GetIsItemPropertyValid(prop))
    {
        int ptype = GetItemPropertyType(prop);
        int psubtype = GetItemPropertySubType(prop);
        int param1 = GetItemPropertyParam1(prop);
        int param1val = GetItemPropertyParam1Value(prop);
        int costTable = GetItemPropertyCostTable(prop);
        int costTableValue = GetItemPropertyCostTableValue(prop);

        if (costTableValue > 50 || costTableValue < 0)
        {
            RemoveItemProperty(oItem, prop);
        }
        else
        {
            filterSignature(oItem, prop, ptype, psubtype, param1, param1val, costTable, costTableValue);
        }

        prop = GetNextItemProperty(oItem);
    }
}

// Custome filter for aquired signature.
// Use this section to add item property signatures that get
// through the filtering process. Think of this as a virus
// scanners signature section for detection. Each item property
// has it's own numerical signature. Use the sd_item_output scanning
// script on a barrel or something to get the items properties.
//
// Note the signature for test crash arrows have already been added.
// Those arrows have 4 properties that make them what they are.
// My thinking was to group items by the ptype. For example, ptypes of
// 10 would have their own if block. Makes for easier organization I think
// of common property type values.
//
// Finally take note how I do AC, AB, Enhance, and Damges for badstreff.
// I leave out the costTableValue to cover the whole range of values for that
// particular property. Becareful what you put in there for removing a bunch in
// one if block. You may end up stepping on a legitmate property.
//
void filterSignature(object oItem, itemproperty prop, int ptype, int psubtype,
                     int param1, int param1val, int costTable, int costTableValue)
{
    if (ptype == 7)
    {
        // Nail Enhance vs. BadStreff.
        if (psubtype == 0 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 255 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 9)
    {
        // Special thanks to Hatred for donating his Pain Kami's.
        if (psubtype == 0 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 9 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 255 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 Enhance vs BS
        if (psubtype == 99 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 16)
    {
        // Test Arrow Property Removal.
        if (psubtype == 197 && param1 == 255 && param1val == 0 && costTable == 4 && costTableValue == 10)
        {
            RemoveItemProperty(oItem, prop);
        }
        // Test Arrow Property Removal.
        else if (psubtype == 200 && param1 == 255 && param1val == 0 && costTable == 4 && costTableValue == 10)
        {
            RemoveItemProperty(oItem, prop);
        }
        // Test Arrow Property Removal.
        else if (psubtype == 203 && param1 == 255 && param1val == 0 && costTable == 4 && costTableValue == 10)
        {
            RemoveItemProperty(oItem, prop);
        }
        // Test Arrow Property Removal.
        else if (psubtype == 204 && param1 == 255 && param1val == 0 && costTable == 4 && costTableValue == 8)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 17)
    {
        // Badstreff Damage vs. Chaotic
        if (psubtype == 3 && param1 == 0 && param1val == 238 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 18)
    {
        // BS physical damage type.
        if (psubtype == 6 && param1 == 0 && param1val == 14 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // Fire Damage vs badstreff
        if (psubtype == 234 && param1 == 0 && param1val == 10 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 Damage vs BS Dwarf
        if (psubtype == 0 && param1 == 0 && param1val == 238 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 Damage vs BS Elf
        if (psubtype == 1 && param1 == 0 && param1val == 238 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 Damage vs BS Half-Elf
        if (psubtype == 4 && param1 == 0 && param1val == 238 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 Damage vs BS Human
        if (psubtype == 6 && param1 == 0 && param1val == 238 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 Damage vs BS Orc
        if (psubtype == 14 && param1 == 0 && param1val == 238 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 BS Damage
        if (psubtype == 28 && param1 == 0 && param1val == 0 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 28 && param1 == 0 && param1val == 8 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 28 && param1 == 0 && param1val == 5 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 28 && param1 == 0 && param1val == 11 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 28 && param1 == 0 && param1val == 1 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 28 && param1 == 0 && param1val == 12 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 28 && param1 == 0 && param1val == 2 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 19)
    {   // Special thanks to Hatred for donating his Pain Kami's.
        if (psubtype == 255 && param1 == 0 && param1val == 0 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 255 && param1 == 0 && param1val == 1 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 255 && param1 == 0 && param1val == 2 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 9 && param1 == 0 && param1val == 0 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 9 && param1 == 0 && param1val == 1 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 9 && param1 == 0 && param1val == 2 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12-6-2004 BS Damage
        if (psubtype == 99 && param1 == 0 && param1val == 11 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 99 && param1 == 0 && param1val == 0 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 99 && param1 == 0 && param1val == 8 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 99 && param1 == 0 && param1val == 12 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 99 && param1 == 0 && param1val == 13 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 99 && param1 == 0 && param1val == 1 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
        if (psubtype == 99 && param1 == 0 && param1val == 2 && costTable == 4)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 23)
    {
        if (psubtype == 197 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 198 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 199 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 200 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 201 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 202 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 203 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 204 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 205 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 206 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 238 && param1 == 255 && param1val == 0 && costTable == 12)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 238 && param1 == 255 && param1val == 0 && costTable == 7)
        {
            RemoveItemProperty(oItem, prop);
        }
        else if (psubtype == 28 && param1 == 0 && param1val == 238 && costTable == 7)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 57)
    {
        // Nail AB vs. BadStreff.
        if (psubtype == 0 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
    if (ptype == 59)
    {
        // Special thanks to Hatred for donating his Pain Kami's.
        if (psubtype == 255 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
        // 12/6/2004 AB vs BS
        if (psubtype == 9 && param1 == 255 && param1val == 0 && costTable == 2)
        {
            RemoveItemProperty(oItem, prop);
        }
    }
}
