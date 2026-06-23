#include "hgll_const_inc"
#include "hgll_struct_stat"
#include "hgll_featreq_inc"
#include "hgll_classft_inc"
#include "hgll_leto_inc"
#include "aps_include"
//--------------------------------DECLARATIONS--------------------------------//

// This returns the current legendary level ("LL") of the PC. It is designed to
// work hand in hand with DAR subraces by tracking level by entering it in
// the (normally unused on PCs) Lootable field on the character file (".bic file").
// If you are not using DAR, it will still function correctly, using GetHitDice to
// track non-legendary levels.
int CheckLegendaryLevel(object oPC);
// This function determines whether a PC has enough experience to take the next legendary
// level.  Possible return values: 1 for having enough, 0 for not, -1 for having too few
// levels to gain Legendary levels, and -2 for already having the maximum amount of LL.
int GetHasXPForNextLL(object oPC);
// This function was used to remove xp from a character based on what LL they were taking.
// It subtracted XP and then returned the XP that was subtracted. It returns zero if they
// are level 60 and -1 if they aren't level 40 yet. It is not used in the current configuration,
// which just lets the xp keep adding up, rather than subtracting the xp after the level is
// gained. This ensures that the character doesn't lose the experience that accrued if for some
// reason Letoscript misfires and fails to edit the character.
int SubtractXPForNextLL(object oPC);
// This function returns the amount of XP the PC is missing to reach their next LL. It will
// return the amount needed to reach level 41 if they are under level 40. If they already
// have enough, it returns 0. If they are level 60, it returns -1.
int GetXPNeededForNextLL(object oPC);
// This function checks for whether or not the PC gains a feat this level. By default it
// is set to one every three levels, carrying the progression of character feats onward from
// the last standard one received at 39, adding new feats starting at level 42 and ending at
// level 60. It is easily modified so that you can assign feats at whatever levels desired.
int GetGainsFeatOnLevelUp(object oPC);
// This function checks for whether or not the PC gains a stat this level. By default it
// is set to one every two levels, doubling the progression of character stats onward from
// the last standard one received at 40, adding new stats starting at level 42 and ending at
// level 60. It is easily modified so that you can assign stats at whatever levels desired.
int GetGainsStatOnLevelUp(object oPC);
// This function tells the caller whether the PC gains +1 to saving throws this level. By default
// it is set to one every four levels, halving the progression of character saves onward from
// the last standard increase received at 40, increasing saves starting at level 44 and ending at
// level 60. It is easily modified so that you can increase saves at whatever levels desired.
int GetGainsSavesOnLevelUp(object oPC);
// This function permanently tags a PC with the CLASS_TYPE that controls his LLs.
void SetControlClass(object oPC, int nClass);
// This function is where any other requirements besides experence and level
// are added to GetHasXPForNextLL. It returns TRUE by default unless modified.
int GetCanGainLL(object oPC);
// This function outputs debugging info to the player and log, but only if DEBUG is
// set to TRUE in hgll_const_inc.
void DoDebug(object oPC, string sDebug);
// This function calculates the Base Ability Scores and Skills of a character, including
// improvements by level and by feats, but filtering out bonuses from gear and effects.
// Skills need another round of filtering before they arrive at base levels.
// sWP: If you specify a WayPoint Tag in an inaccesible area, the clones will be
// generated there.
struct xAbility GetRoughAbilities(object oPC, string sWP="");
// This function returns the number of Great Strenth feats the character has.
int GetHasGreatStrenth(object oPC);
// This function returns the number of Great Dexterity feats the character has.
int GetHasGreatDexterity(object oPC);
// This function returns the number of Great Constitution feats the character has.
int GetHasGreatConstitution(object oPC);
// This function returns the number of Great Intelligence feats the character has.
int GetHasGreatIntelligence(object oPC);
// This function returns the number of Great Wisdom feats the character has.
int GetHasGreatWisdom(object oPC);
// This function returns the number of Great Charisma feats the character has.
int GetHasGreatCharisma(object oPC);
// This function filters out the Greater Stat Feats and Red Dragon Disciple ability bonuses
// from the ability scores.
int GetBaseStat(int nStatType, int nStat, object oPC);
// This function returns the Red Dragon Disciple ability bonus the character has for the
// specified ability.
int GetRDDStatMod(int nStatType, object oPC);
// This function returns the point vaule penalty (a positive number) for
// dexterity-based skills of the armor worn by the PC.
int GetArmorPenalty(object oPC);
// This function returns the point vaule penalty (a positive number) for
// dexterity-based skills of the shield worn by the PC.
int GetShieldPenalty(object oPC);
// This function takes a given stat number and calculates the bonus from it.
int GetBaseAbilityModifier(int nAmount);
// This function takes the scores retrieved from the GetRoughAbilities function and
// subtracts feat and ability bonuses from the skill to arrive at final base skill.
int GetBaseSkill(int nSkill, struct xAbility stat, object oPC);
// This function calculates the values of all the characters base skills,
// after adjusting them for stat modifiers and feats via GetBaseSkill.
struct xAbility GetBaseAbilities(struct xAbility stat, object oPC);
// This function sets local ints indicating the base ability for all 6 ability scores and
// all 27 skills. They are called later to help determine dependant characteristics like
// hitpoints, and are used to determine feat availabilities, etc.
void SetBaseAbilityMarkers(struct xAbility stat, object oPC);
//This function deletes all the ints tracking base ability and skill scores.
void DeleteBaseAbilityMarkers(object oPC);
// This function determines and returns the amount of skill points a character will get each
// LL based on their control class, INT modifier, and their main race (humans get +1)
int GetSkillPointsGainedOnLevelUp(object oPC);
// This function determines whether a skill is available to the charcter and should appear on the
// skill list, based on the character's control class, the amount of points they have remaining,
// the cost of the skill for the control class, and their current skill level in the skill.
int GetIsSkillAvailable(object oPC, int nSkill);
// This function returns the name string of the specified skill.
string GetNameOfSkill(int nSkill);
// This function returns the name of the tracking int for the specified skill.
string GetNameOfTrackingInt(int nSkill);
// This function determines the amount of HP that a character gets on levelup based on their
// control class, their CON modifier, and whether or not they've taken the toughness feat.
int GetHitPointsGainedOnLevelUp(object oPC);
// This function restores all limited usage feats so that GetHasFeat will not
// return a false negative.
void ReplenishLimitedUseFeats(object oPC);
// This function determines whether a feat is available to the charcter and should appear on the
// feat list, based on the character's control class, whether they meet the feat's requirements,
// whether they already have the feat, and whether the feat is restricted.
int GetIsFeatAvailable(int nFeat, object oPC);
// This function returns the name of the designated ability score.
string GetNameOfAbility(int nStat);
// This function returns the display name of the specified class constant, used to
// tell the player which "control class" their available skills are based on.
string GetNameOfClass(int nClass);
// This function returns TRUE if the specified feat is a class feat and the character has
// enough levels in the class to take it. Otherwise it returns FALSE.
int GetIsClassFeat(int nFeat, int nClass, object oPC);

//----------------------------------FUNCTIONS---------------------------------//

int CheckLegendaryLevel(object oPC)
{
int nLevel = HGLL_GetDocumentedLevel(oPC);
if (nLevel<41)
    {
    return GetHitDice(oPC);
    }
else
    {
    return nLevel;
    }
}

int GetHasXPForNextLL(object oPC)
{
switch(CheckLegendaryLevel(oPC))
    {
    case 40: return (XP_REQ_LVL41-GetXP(oPC)<=0); break;
    case 41: return (XP_REQ_LVL42-GetXP(oPC)<=0); break;
    case 42: return (XP_REQ_LVL43-GetXP(oPC)<=0); break;
    case 43: return (XP_REQ_LVL44-GetXP(oPC)<=0); break;
    case 44: return (XP_REQ_LVL45-GetXP(oPC)<=0); break;
    case 45: return (XP_REQ_LVL46-GetXP(oPC)<=0); break;
    case 46: return (XP_REQ_LVL47-GetXP(oPC)<=0); break;
    case 47: return (XP_REQ_LVL48-GetXP(oPC)<=0); break;
    case 48: return (XP_REQ_LVL49-GetXP(oPC)<=0); break;
    case 49: return (XP_REQ_LVL50-GetXP(oPC)<=0); break;
    case 50: return (XP_REQ_LVL51-GetXP(oPC)<=0); break;
    case 51: return (XP_REQ_LVL52-GetXP(oPC)<=0); break;
    case 52: return (XP_REQ_LVL53-GetXP(oPC)<=0); break;
    case 53: return (XP_REQ_LVL54-GetXP(oPC)<=0); break;
    case 54: return (XP_REQ_LVL55-GetXP(oPC)<=0); break;
    case 55: return (XP_REQ_LVL56-GetXP(oPC)<=0); break;
    case 56: return (XP_REQ_LVL57-GetXP(oPC)<=0); break;
    case 57: return (XP_REQ_LVL58-GetXP(oPC)<=0); break;
    case 58: return (XP_REQ_LVL59-GetXP(oPC)<=0); break;
    case 59: return (XP_REQ_LVL60-GetXP(oPC)<=0); break;
    case 60: return -2; break;
    default: return -1; break;
    }
    return -3;
}

int SubtractXPForNextLL(object oPC)
{
switch(CheckLegendaryLevel(oPC))
    {
    case 40: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL41)); return XP_REQ_LVL41; break;
    case 41: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL42)); return XP_REQ_LVL42; break;
    case 42: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL43)); return XP_REQ_LVL43; break;
    case 43: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL44)); return XP_REQ_LVL44; break;
    case 44: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL45)); return XP_REQ_LVL45; break;
    case 45: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL46)); return XP_REQ_LVL46; break;
    case 46: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL47)); return XP_REQ_LVL47; break;
    case 47: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL48)); return XP_REQ_LVL48; break;
    case 48: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL49)); return XP_REQ_LVL49; break;
    case 49: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL50)); return XP_REQ_LVL50; break;
    case 50: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL51)); return XP_REQ_LVL51; break;
    case 51: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL52)); return XP_REQ_LVL52; break;
    case 52: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL53)); return XP_REQ_LVL53; break;
    case 53: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL54)); return XP_REQ_LVL54; break;
    case 54: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL55)); return XP_REQ_LVL55; break;
    case 55: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL56)); return XP_REQ_LVL56; break;
    case 56: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL57)); return XP_REQ_LVL57; break;
    case 57: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL58)); return XP_REQ_LVL58; break;
    case 58: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL59)); return XP_REQ_LVL59; break;
    case 59: SetXP(oPC,(GetXP(oPC)-XP_REQ_LVL60)); return XP_REQ_LVL60; break;
    case 60: return 0; break;
    default: return -1; break;
    }
    return -3;
}

int GetXPNeededForNextLL(object oPC)
{
int nXP;
switch(CheckLegendaryLevel(oPC))
    {
    case 40: nXP = XP_REQ_LVL41-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 41: nXP = XP_REQ_LVL42-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 42: nXP = XP_REQ_LVL43-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 43: nXP = XP_REQ_LVL44-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 44: nXP = XP_REQ_LVL45-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 45: nXP = XP_REQ_LVL46-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 46: nXP = XP_REQ_LVL47-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 47: nXP = XP_REQ_LVL48-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 48: nXP = XP_REQ_LVL49-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 49: nXP = XP_REQ_LVL50-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 50: nXP = XP_REQ_LVL51-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 51: nXP = XP_REQ_LVL52-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 52: nXP = XP_REQ_LVL53-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 53: nXP = XP_REQ_LVL54-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 54: nXP = XP_REQ_LVL55-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 55: nXP = XP_REQ_LVL56-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 56: nXP = XP_REQ_LVL57-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 57: nXP = XP_REQ_LVL58-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 58: nXP = XP_REQ_LVL59-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 59: nXP = XP_REQ_LVL60-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    case 60: nXP = -1;
    default: nXP = XP_REQ_LVL41-(GetXP(oPC)); if(nXP<=0) nXP = 0; break;
    }
return nXP;
}

int GetGainsFeatOnLevelUp(object oPC)
{
switch(CheckLegendaryLevel(oPC))
    {
    case 41: return 1; break;
    case 44: return 1; break;
    case 47: return 1; break;
    case 50: return 1; break;
    case 53: return 1; break;
    case 56: return 1; break;
    case 59: return 1; break;
    default: return 0; break;
    }
    return -3;
}

int GetGainsStatOnLevelUp(object oPC)
{
switch(CheckLegendaryLevel(oPC))
    {
    case 41: return 1; break;
    case 43: return 1; break;
    case 45: return 1; break;
    case 47: return 1; break;
    case 49: return 1; break;
    case 51: return 1; break;
    case 53: return 1; break;
    case 55: return 1; break;
    case 57: return 1; break;
    case 59: return 1; break;
    default: return 0; break;
    }
    return -3;
}

int GetGainsSavesOnLevelUp(object oPC)
{
    switch(CheckLegendaryLevel(oPC))
    {
        case 43:
        case 47:
        case 51:
        case 55:
        case 59: return 1; break;
        default: return 0; break;
    }
    return -3;
}

void SetControlClass(object oPC, int nClass)
{
// NWNX:EE replacement for the dead NWNX2/APS GetPersistentInt path. APS's
// GetPersistentInt returns the sentinel -2147483647 when no ODBC plugin
// fulfils the query, which corrupts PointsAvailable on first LL.
NWNX_Object_SetInt(oPC, "hgll_control_class", nClass, TRUE);
DoDebug(oPC, "Control Class: " + IntToString(nClass));
}



int GetCanGainLL(object oPC)
{
string immortalname;
string sName = GetName(oPC);
immortalname = GetStringLeft(sName, 8) + GetStringRight(sName, 8) + GetStringLeft(GetPCPlayerName(oPC), 8) + GetStringRight(GetPCPlayerName(oPC), 8);
int nImmortal = 2;//GetLocalInt(oPC, immortalname);
if (nImmortal == 2) return TRUE;
return FALSE;
}

void DoDebug(object oPC, string sDebug)
{
if (DEBUG)
    {
    WriteTimestampedLogEntry(sDebug);
    SendMessageToPC(oPC, sDebug);
    }
}

struct xAbility GetRoughAbilities(object oPC, string sWP="")
{
    effect eEffect;
    itemproperty ipPenalty;
    int iCount;
    int nValue;
    int nValue2;
    int nClass = GetControlClass(oPC);
    object oItem, oWP, oClone;
    location lClone;
    struct xAbility xAbility;
    for(iCount = 0; iCount < NUM_INVENTORY_SLOTS; iCount++)
    {
        oItem = GetItemInSlot(iCount, oPC);
        if(GetIsObjectValid(oItem))
        {
            ipPenalty = GetFirstItemProperty(oItem);
            while(GetIsItemPropertyValid(ipPenalty))
            {
                if(GetItemHasItemProperty(oItem, ITEM_PROPERTY_DECREASED_ABILITY_SCORE))
                {
                    if(GetItemPropertyType(ipPenalty) == ITEM_PROPERTY_DECREASED_ABILITY_SCORE)
                    {
                        nValue = GetItemPropertyCostTableValue(ipPenalty);//will return between -1 and -10, matching the maximum penalty to skills from any given item
                        switch(GetItemPropertySubType(ipPenalty))
                        {
                            case ABILITY_STRENGTH:      xAbility.nSTR += nValue;  break;
                            case ABILITY_DEXTERITY:     xAbility.nDEX += nValue;  break;
                            case ABILITY_CONSTITUTION:  xAbility.nCON += nValue;  break;
                            case ABILITY_INTELLIGENCE:  xAbility.nINT += nValue;  break;
                            case ABILITY_WISDOM:        xAbility.nWIS += nValue;  break;
                            case ABILITY_CHARISMA:      xAbility.nCHA += nValue;  break;
                        }
                    }
                }
                if(GetItemHasItemProperty(oItem, ITEM_PROPERTY_DECREASED_SKILL_MODIFIER))
                {
                    if(GetItemPropertyType(ipPenalty) == ITEM_PROPERTY_DECREASED_SKILL_MODIFIER)
                    {
                        nValue2 = GetItemPropertyCostTableValue(ipPenalty);//will return between -1 and -10, matching the maximum penalty to skills from any given item
                        switch(GetItemPropertySubType(ipPenalty))
                        {
                            case SKILL_ANIMAL_EMPATHY:      xAbility.nANIMAL_EMPATHY += nValue2;  break;
                            case SKILL_CONCENTRATION:       xAbility.nCONCENTRATION += nValue2;  break;
                            case SKILL_DISABLE_TRAP:        xAbility.nDISABLE_TRAP += nValue2;  break;
                            case SKILL_DISCIPLINE:          xAbility.nDISCIPLINE += nValue2;  break;
                            case SKILL_HEAL:                xAbility.nHEAL += nValue2;  break;
                            case SKILL_HIDE:                xAbility.nHIDE += nValue2;  break;
                            case SKILL_LISTEN:              xAbility.nLISTEN += nValue2;  break;
                            case SKILL_LORE:                xAbility.nLORE += nValue2;  break;
                            case SKILL_MOVE_SILENTLY:       xAbility.nMOVE_SILENTLY += nValue2;  break;
                            case SKILL_OPEN_LOCK:           xAbility.nOPEN_LOCK += nValue2;  break;
                            case SKILL_PARRY:               xAbility.nPARRY += nValue2;  break;
                            case SKILL_PERFORM:             xAbility.nPERFORM += nValue2;  break;
                            case SKILL_PERSUADE:            xAbility.nPERSUADE += nValue2;  break;
                            case SKILL_PICK_POCKET:         xAbility.nPICK_POCKET += nValue2;  break;
                            case SKILL_SEARCH:              xAbility.nSEARCH += nValue2;  break;
                            case SKILL_SET_TRAP:            xAbility.nSET_TRAP += nValue2;  break;
                            case SKILL_SPELLCRAFT:          xAbility.nSPELLCRAFT += nValue2;  break;
                            case SKILL_SPOT:                xAbility.nSPOT += nValue2;  break;
                            case SKILL_TAUNT:               xAbility.nTAUNT += nValue2;  break;
                            case SKILL_USE_MAGIC_DEVICE:    xAbility.nUSE_MAGIC_DEVICE += nValue2;  break;
                            case SKILL_APPRAISE:            xAbility.nAPPRAISE += nValue2;  break;
                            case SKILL_TUMBLE:              xAbility.nTUMBLE += nValue2;  break;
                            case SKILL_CRAFT_TRAP:          xAbility.nCRAFT_TRAP += nValue2;  break;
                            case SKILL_BLUFF:               xAbility.nBLUFF += nValue2;  break;
                            case SKILL_INTIMIDATE:          xAbility.nINTIMIDATE += nValue2;  break;
                            case SKILL_CRAFT_ARMOR:         xAbility.nCRAFT_ARMOR += nValue2;  break;
                            case SKILL_CRAFT_WEAPON:        xAbility.nCRAFT_WEAPON += nValue2;  break;
                        }
                    }
                }
                ipPenalty = GetNextItemProperty(oItem);
            }
        }
    }
    //Create Clone
    oWP = GetWaypointByTag(sWP);
    lClone = GetLocation(oWP);
    if(sWP != "" && oWP != OBJECT_INVALID && GetAreaFromLocation(lClone)!= OBJECT_INVALID)
    {
        lClone = GetLocation(oWP);
    }
    else
    {
        lClone = GetLocation(oPC);
    }
    oClone = CopyObject(oPC,lClone);
    //Remove Effects from Clone
    eEffect = GetFirstEffect(oClone);
    while(GetEffectType(eEffect) != EFFECT_TYPE_INVALIDEFFECT)
    {
        RemoveEffect(oClone, eEffect);
        eEffect = GetNextEffect(oClone);
    }
    for(iCount = 0; iCount < 6; iCount++)
    {
        eEffect = EffectAbilityIncrease(iCount, 12);
        ApplyEffectToObject(DURATION_TYPE_PERMANENT, eEffect, oClone);
        nValue = GetAbilityScore(oClone, iCount);
        switch(iCount)
        {
            case ABILITY_STRENGTH:      if(xAbility.nSTR >= -10) xAbility.nSTR += nValue - 12; else xAbility.nSTR = nValue - 2;  break;
            case ABILITY_DEXTERITY:     if(xAbility.nDEX >= -10) xAbility.nDEX += nValue - 12; else xAbility.nDEX = nValue - 2;  break;
            case ABILITY_CONSTITUTION:  if(xAbility.nCON >= -10) xAbility.nCON += nValue - 12; else xAbility.nCON = nValue - 2;  break;
            case ABILITY_INTELLIGENCE:  if(xAbility.nINT >= -10) xAbility.nINT += nValue - 12; else xAbility.nINT = nValue - 2;  break;
            case ABILITY_WISDOM:        if(xAbility.nWIS >= -10) xAbility.nWIS += nValue - 12; else xAbility.nWIS = nValue - 2;  break;
            case ABILITY_CHARISMA:      if(xAbility.nCHA >= -10) xAbility.nCHA += nValue - 12; else xAbility.nCHA = nValue - 2;  break;
        }
    }
    for(iCount = 0; iCount < 27; iCount++)
    {
        //eEffect = EffectSkillIncrease(iCount, 50);
        ApplyEffectToObject(DURATION_TYPE_PERMANENT, eEffect, oClone);
        nValue = GetSkillRank(iCount, oClone);
        switch(iCount)//we subtract and extra 6 here for the stats being at +12, for a total of -56
        {
            case SKILL_ANIMAL_EMPATHY:      if(xAbility.nANIMAL_EMPATHY >= -10) xAbility.nANIMAL_EMPATHY += nValue - 6; else xAbility.nANIMAL_EMPATHY = nValue - 2;  break;
            case SKILL_CONCENTRATION:       if(xAbility.nCONCENTRATION >= -10) xAbility.nCONCENTRATION += nValue - 6; else xAbility.nCONCENTRATION = nValue - 2;  break;
            case SKILL_DISABLE_TRAP:        if(xAbility.nDISABLE_TRAP >= -10) xAbility.nDISABLE_TRAP += nValue - 6; else xAbility.nDISABLE_TRAP = nValue - 2;  break;
            case SKILL_DISCIPLINE:          if(xAbility.nDISCIPLINE >= -10) xAbility.nDISCIPLINE += nValue - 6; else xAbility.nDISCIPLINE = nValue - 2;  break;
            case SKILL_HEAL:                if(xAbility.nHEAL >= -10) xAbility.nHEAL += nValue - 6; else xAbility.nHEAL = nValue - 2;  break;
            case SKILL_HIDE:                if(xAbility.nHIDE >= -10) xAbility.nHIDE += nValue - 6; else xAbility.nHIDE = nValue - 2;  break;
            case SKILL_LISTEN:              if(xAbility.nLISTEN >= -10) xAbility.nLISTEN += nValue - 6; else xAbility.nLISTEN = nValue - 2;  break;
            case SKILL_LORE:                if(xAbility.nLORE >= -10) xAbility.nLORE += nValue - 6; else xAbility.nLORE = nValue - 2;  break;
            case SKILL_MOVE_SILENTLY:       if(xAbility.nMOVE_SILENTLY >= -10) xAbility.nMOVE_SILENTLY += nValue - 6; else xAbility.nMOVE_SILENTLY = nValue - 2;  break;
            case SKILL_OPEN_LOCK:           if(xAbility.nOPEN_LOCK >= -10) xAbility.nOPEN_LOCK += nValue - 6; else xAbility.nOPEN_LOCK = nValue - 2;  break;
            case SKILL_PARRY:               if(xAbility.nPARRY >= -10) xAbility.nPARRY += nValue - 6; else xAbility.nPARRY = nValue - 2;  break;
            case SKILL_PERFORM:             if(xAbility.nPERFORM >= -10) xAbility.nPERFORM += nValue - 6; else xAbility.nPERFORM = nValue - 2;  break;
            case SKILL_PERSUADE:            if(xAbility.nPERSUADE >= -10) xAbility.nPERSUADE += nValue - 6; else xAbility.nPERSUADE = nValue - 2;  break;
            case SKILL_PICK_POCKET:         if(xAbility.nPICK_POCKET >= -10) xAbility.nPICK_POCKET += nValue - 6; else xAbility.nPICK_POCKET = nValue - 2;  break;
            case SKILL_SEARCH:              if(xAbility.nSEARCH >= -10) xAbility.nSEARCH += nValue - 6; else xAbility.nSEARCH = nValue - 2;  break;
            case SKILL_SET_TRAP:            if(xAbility.nSET_TRAP >= -10) xAbility.nSET_TRAP += nValue - 6; else xAbility.nSET_TRAP = nValue - 2;  break;
            case SKILL_SPELLCRAFT:          if(xAbility.nSPELLCRAFT >= -10) xAbility.nSPELLCRAFT += nValue - 6; else xAbility.nSPELLCRAFT = nValue - 2;  break;
            case SKILL_SPOT:                if(xAbility.nSPOT >= -10) xAbility.nSPOT += nValue - 6; else xAbility.nSPOT = nValue - 2;  break;
            case SKILL_TAUNT:               if(xAbility.nTAUNT >= -10) xAbility.nTAUNT += nValue - 6; else xAbility.nTAUNT = nValue - 2;  break;
            case SKILL_USE_MAGIC_DEVICE:    if(xAbility.nUSE_MAGIC_DEVICE >= -10) xAbility.nUSE_MAGIC_DEVICE += nValue - 6; else xAbility.nUSE_MAGIC_DEVICE = nValue - 2;  break;
            case SKILL_APPRAISE:            if(xAbility.nAPPRAISE >= -10) xAbility.nAPPRAISE += nValue - 6; else xAbility.nAPPRAISE = nValue - 2;  break;
            case SKILL_TUMBLE:              if(xAbility.nTUMBLE >= -10) xAbility.nTUMBLE += nValue - 6; else xAbility.nTUMBLE = nValue - 2;  break;
            case SKILL_CRAFT_TRAP:          if(xAbility.nCRAFT_TRAP >= -10) xAbility.nCRAFT_TRAP += nValue - 6; else xAbility.nCRAFT_TRAP = nValue - 2;  break;
            case SKILL_BLUFF:               if(xAbility.nBLUFF >= -10) xAbility.nBLUFF += nValue - 6; else xAbility.nBLUFF = nValue - 2;  break;
            case SKILL_INTIMIDATE:          if(xAbility.nINTIMIDATE >= -10) xAbility.nINTIMIDATE += nValue - 6; else xAbility.nINTIMIDATE = nValue - 2;  break;
            case SKILL_CRAFT_ARMOR:         if(xAbility.nCRAFT_ARMOR >= -10) xAbility.nCRAFT_ARMOR += nValue - 6; else xAbility.nCRAFT_ARMOR = nValue - 2;  break;
            case SKILL_CRAFT_WEAPON:        if(xAbility.nCRAFT_WEAPON >= -10) xAbility.nCRAFT_WEAPON += nValue - 6; else xAbility.nCRAFT_WEAPON = nValue - 2;  break;
        }
    }
//dont try to destroy or take the clone items, wont work
DestroyObject(oClone);
return xAbility;
}

int GetBaseAbilityModifier(int nAmount)
{
    if ((nAmount%2)==0)
        {
        nAmount = (nAmount/2)+(nAmount%2);
        nAmount = nAmount-5;
        }
    else
        {
        nAmount = (nAmount/2)+(nAmount%2);
        nAmount = nAmount-6;
        }
    return nAmount;
}

int GetHasGreatStrenth(object oPC)
{
    int nFeat = 0;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_1,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_2,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_3,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_4,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_5,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_6,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_7,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_8,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_9,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_STRENGTH_10,oPC)) nFeat++;
    return nFeat;
}

int GetHasGreatDexterity(object oPC)
{
    int nFeat = 0;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_1,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_2,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_3,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_4,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_5,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_6,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_7,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_8,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_9,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_DEXTERITY_10,oPC)) nFeat++;
    return nFeat;
}

int GetHasGreatConstitution(object oPC)
{
    int nFeat = 0;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_1,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_2,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_3,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_4,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_5,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_6,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_7,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_8,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_9,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CONSTITUTION_10,oPC)) nFeat++;
    return nFeat;
}

int GetHasGreatIntelligence(object oPC)
{
    int nFeat = 0;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_1,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_2,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_3,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_4,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_5,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_6,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_7,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_8,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_9,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_INTELLIGENCE_10,oPC)) nFeat++;
    return nFeat;
}

int GetHasGreatWisdom(object oPC)
{
    int nFeat = 0;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_1,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_2,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_3,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_4,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_5,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_6,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_7,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_8,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_9,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_WISDOM_10,oPC)) nFeat++;
    return nFeat;
}

int GetHasGreatCharisma(object oPC)
{
    int nFeat = 0;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_1,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_2,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_3,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_4,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_5,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_6,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_7,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_8,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_9,oPC)) nFeat++;
    if(GetHasFeat(FEAT_EPIC_GREAT_CHARISMA_10,oPC)) nFeat++;
    return nFeat;
}

int GetBaseStat(int nStatType, int nStat, object oPC)
{
int nSubtract = 0;
int nBase;
switch(nStatType)
    {
    case ABILITY_STRENGTH:
        nSubtract = GetHasGreatStrenth(oPC) + GetRDDStatMod(nStatType, oPC);
        nBase = nStat; break;
    case ABILITY_DEXTERITY:
        nSubtract = GetHasGreatDexterity(oPC) + GetRDDStatMod(nStatType, oPC);
        nBase = nStat; break ;
    case ABILITY_CONSTITUTION:
        nSubtract = GetHasGreatConstitution(oPC) + GetRDDStatMod(nStatType, oPC);;
        nBase = nStat; break;
    case ABILITY_INTELLIGENCE:
        nSubtract = GetHasGreatIntelligence(oPC) + GetRDDStatMod(nStatType, oPC);;
        nBase = nStat; break;
    case ABILITY_WISDOM:
        nSubtract = GetHasGreatWisdom(oPC) + GetRDDStatMod(nStatType, oPC);;
        nBase = nStat; break;
    case ABILITY_CHARISMA:
        nSubtract = GetHasGreatCharisma(oPC) + GetRDDStatMod(nStatType, oPC);;
        nBase = nStat; break;
    default: return -3;  break;
    }
return (nBase-nSubtract);
}

int GetRDDStatMod(int nStatType, object oPC)
{
int nRDDLevel = GetLevelByClass(CLASS_TYPE_DRAGONDISCIPLE, oPC);
int nReturn = 0;
if (nRDDLevel < 1) return 0;//if not rdd, return
switch(nStatType)
    {
    case ABILITY_STRENGTH:
         if (nRDDLevel > 9) nReturn = 8;
         else if (nRDDLevel > 3) nReturn = 4;
         else if (nRDDLevel > 1) nReturn = 2;
         else nReturn = 0;
         break;
    case ABILITY_DEXTERITY:
         if (nRDDLevel > 6) nReturn = 2;
         else nReturn = 0;
         break;
    case ABILITY_CONSTITUTION:

    case ABILITY_INTELLIGENCE:
         if (nRDDLevel > 8) nReturn = 2;
         else nReturn = 0;
         break;
    case ABILITY_WISDOM:
         nReturn = 0;
         break;
    case ABILITY_CHARISMA:
         if (nRDDLevel > 9) nReturn = 2;
         else nReturn = 0;
         break;
    }
return nReturn;
}

int GetArmorPenalty(object oPC)
{
    object oItem = GetItemInSlot(INVENTORY_SLOT_CHEST, oPC);
    if (!GetIsObjectValid(oItem)) return 0;
    if (GetBaseItemType(oItem) != BASE_ITEM_ARMOR) return 0;
    SetIdentified(oItem,FALSE);
    int nPenalty = 0;
    switch (GetGoldPieceValue(oItem))
        {
        case    1: nPenalty = 0; break;
        case    5: nPenalty = 0; break;
        case   10: nPenalty = 0; break;
        case   15: nPenalty = 1; break;
        case  100: nPenalty = 2; break;
        case  150: nPenalty = 5; break;
        case  200: nPenalty = 7; break;
        case  600: nPenalty = 7; break;
        case 1500: nPenalty = 8; break;
        }
    SetIdentified(oItem,TRUE);
    return nPenalty;
}

int GetShieldPenalty(object oPC)
{
    object oItem = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    if (!GetIsObjectValid(oItem)) return 0;
    int nType = GetBaseItemType(oItem);
    int nPenalty = 0;
    switch(nType)
        {
        case BASE_ITEM_SMALLSHIELD: nPenalty = 1; break;
        case BASE_ITEM_LARGESHIELD: nPenalty = 2; break;
        case BASE_ITEM_TOWERSHIELD: nPenalty = 10; break;
        default: nPenalty = 0; break;
        }
    return nPenalty;
}

int GetBaseSkill(int nSkill, struct xAbility stat, object oPC)
{
int nSubtract = 0;
int nModifier = 0;
int nBase = 0;
int nArmorShield = 0;
int nValue = GetSkillRank(nSkill, oPC);
if (GetCostOfSkill(GetControlClass(oPC), nSkill) == -1 || nValue == 0)
    {
    return 0; //if skill non-available return 0
    }
else
    {
    switch(nSkill)
        {
        case SKILL_ANIMAL_EMPATHY:
            nBase = stat.nANIMAL_EMPATHY;
            if(GetHasFeat(FEAT_SKILL_FOCUS_ANIMAL_EMPATHY,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_ANIMAL_EMPATHY,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier=GetBaseAbilityModifier(stat.nCHA);
            break;
        case SKILL_APPRAISE:
            nBase = stat.nAPPRAISE;
            if(GetHasFeat(FEAT_SILVER_PALM,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILLFOCUS_APPRAISE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_APPRAISE,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_BLUFF:
            nBase = stat.nBLUFF;
            if(GetHasFeat(FEAT_EPIC_REPUTATION,oPC))
            nSubtract=nSubtract+4;
            if(GetHasFeat(FEAT_SKILL_FOCUS_BLUFF,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_BLUFF,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCHA);
            break;
        case SKILL_CONCENTRATION:
            nBase = stat.nCONCENTRATION;
            if(GetHasFeat(FEAT_SKILL_AFFINITY_CONCENTRATION,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_CONCENTRATION,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_CONCENTRATION,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatConstitution(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCON);
            break;
        case SKILL_CRAFT_ARMOR:
            nBase = stat.nCRAFT_ARMOR;
            if(GetHasFeat(FEAT_SKILL_FOCUS_CRAFT_ARMOR,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_CRAFT_ARMOR,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_CRAFT_TRAP:
            nBase = stat.nCRAFT_TRAP;
            if(GetHasFeat(FEAT_SKILL_FOCUS_CRAFT_TRAP,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_CRAFT_TRAP,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_CRAFT_WEAPON:
            nBase = stat.nCRAFT_WEAPON;
            if(GetHasFeat(FEAT_SKILL_FOCUS_CRAFT_WEAPON,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_CRAFT_WEAPON,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_DISABLE_TRAP:
            nBase = stat.nDISABLE_TRAP;
            if(GetHasFeat(FEAT_SKILL_FOCUS_DISABLE_TRAP,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_DISABLETRAP,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_DISCIPLINE:
            nBase = stat.nDISCIPLINE;
            if(GetHasFeat(FEAT_SKILL_FOCUS_DISCIPLINE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_DISCIPLINE,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatStrenth(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nSTR);
            break;
        case SKILL_HEAL:
            nBase = stat.nHEAL;
            if(GetHasFeat(FEAT_SKILL_FOCUS_HEAL,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_HEAL,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatWisdom(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nWIS);
            break;
        case SKILL_HIDE:
            nBase = stat.nHIDE;
            if(GetHasFeat(FEAT_STEALTHY,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_HIDE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_HIDE,oPC))
            nSubtract=nSubtract+10;
            nArmorShield = GetArmorPenalty(oPC) + GetShieldPenalty(oPC);
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_INTIMIDATE:
            nBase = stat.nINTIMIDATE;
            if(GetHasFeat(FEAT_EPIC_REPUTATION,oPC))
            nSubtract=nSubtract+4;
            if(GetHasFeat(FEAT_SKILL_FOCUS_INTIMIDATE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_INTIMIDATE,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCHA);
            break;
        case SKILL_LISTEN:
            nBase = stat.nLISTEN;
            if(GetHasFeat(FEAT_PARTIAL_SKILL_AFFINITY_LISTEN,oPC))
            nSubtract++;
            if(GetHasFeat(FEAT_ALERTNESS,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_AFFINITY_LISTEN,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_LISTEN,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_LISTEN,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatWisdom(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nWIS);
            break;
        case SKILL_LORE:
            nBase = stat.nLORE;
            if(GetHasFeat(FEAT_BARDIC_KNOWLEDGE,oPC))
            nSubtract=nSubtract+GetLevelByClass(CLASS_TYPE_BARD,oPC)+GetLevelByClass(CLASS_TYPE_HARPER);
            if(GetHasFeat(FEAT_SKILL_AFFINITY_LORE,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_COURTLY_MAGOCRACY,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_LORE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_LORE,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_MOVE_SILENTLY:
            nBase = stat.nMOVE_SILENTLY;
            if(GetHasFeat(FEAT_STEALTHY,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_AFFINITY_MOVE_SILENTLY,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_MOVE_SILENTLY,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_MOVESILENTLY,oPC))
            nSubtract=nSubtract+10;
            nArmorShield = GetArmorPenalty(oPC) + GetShieldPenalty(oPC);
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_OPEN_LOCK:
            nBase = stat.nOPEN_LOCK;
            if(GetHasFeat(FEAT_SKILL_FOCUS_OPEN_LOCK,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_OPENLOCK,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_PARRY:
            nBase = stat.nPARRY;
            if(GetHasFeat(FEAT_SKILL_FOCUS_PARRY,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_PARRY,oPC))
            nSubtract=nSubtract+10;
            nArmorShield = GetArmorPenalty(oPC) + GetShieldPenalty(oPC);
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_PERFORM:
            nBase = stat.nPERFORM;
            if(GetHasFeat(FEAT_ARTIST,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_PERFORM,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_PERFORM,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCHA);
            break;
        case SKILL_PERSUADE:
            nBase = stat.nPERSUADE;
            if(GetHasFeat(FEAT_SILVER_PALM,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_THUG,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_EPIC_REPUTATION,oPC))
            nSubtract=nSubtract+4;
            if(GetHasFeat(FEAT_SKILL_FOCUS_PERSUADE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_PERSUADE,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCHA);
            break;
        case SKILL_PICK_POCKET:
            nBase = stat.nPICK_POCKET;
            if(GetHasFeat(FEAT_SKILL_FOCUS_PICK_POCKET,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_PICKPOCKET,oPC))
            nSubtract=nSubtract+10;
            nArmorShield = GetArmorPenalty(oPC) + GetShieldPenalty(oPC);
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_SEARCH:
            nBase = stat.nSEARCH;
            if(GetHasFeat(FEAT_PARTIAL_SKILL_AFFINITY_SEARCH,oPC))
            nSubtract=nSubtract+1;
            if(GetHasFeat(FEAT_SKILL_AFFINITY_SEARCH,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_SEARCH,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_SEARCH,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_SET_TRAP:
            nBase = stat.nSET_TRAP;
            if(GetHasFeat(FEAT_SKILL_FOCUS_SET_TRAP,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_SETTRAP,oPC))
            nSubtract=nSubtract+10;
            nArmorShield = GetArmorPenalty(oPC) + GetShieldPenalty(oPC);
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_SPELLCRAFT:
            nBase = stat.nSPELLCRAFT;
            if(GetHasFeat(FEAT_COURTLY_MAGOCRACY,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_SPELLCRAFT,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_SPELLCRAFT,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatIntelligence(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nINT);
            break;
        case SKILL_SPOT:
            nBase = stat.nSPOT;
            if(GetHasFeat(FEAT_ALERTNESS,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_BLOODED,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_ARTIST,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_PARTIAL_SKILL_AFFINITY_SPOT,oPC))
            nSubtract=nSubtract+1;
            if(GetHasFeat(FEAT_SKILL_AFFINITY_SPOT,oPC))
            nSubtract=nSubtract+2;
            if(GetHasFeat(FEAT_SKILL_FOCUS_SPOT,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_SPOT,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatWisdom(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nWIS);
            break;
        case SKILL_TAUNT:
            nBase = stat.nTAUNT;
            if(GetHasFeat(FEAT_EPIC_REPUTATION,oPC))
            nSubtract=nSubtract+4;
            if(GetHasFeat(FEAT_SKILL_FOCUS_TAUNT,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_TAUNT,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCHA);
            break;
        case SKILL_TUMBLE:
            nBase = stat.nTUMBLE;
            if(GetHasFeat(FEAT_SKILL_FOCUS_TUMBLE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_TUMBLE,oPC))
            nSubtract=nSubtract+10;
            nArmorShield = GetArmorPenalty(oPC) + GetShieldPenalty(oPC);
//            nSubtract = nSubtract + (GetHasGreatDexterity(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nDEX);
            break;
        case SKILL_USE_MAGIC_DEVICE:
            nBase = stat.nUSE_MAGIC_DEVICE;
            if(GetHasFeat(FEAT_SKILL_FOCUS_USE_MAGIC_DEVICE,oPC))
            nSubtract=nSubtract+3;
            if(GetHasFeat(FEAT_EPIC_SKILL_FOCUS_USEMAGICDEVICE,oPC))
            nSubtract=nSubtract+10;
//            nSubtract = nSubtract + (GetHasGreatCharisma(oPC)/2);
            nModifier = GetBaseAbilityModifier(stat.nCHA);
            break;
        default: return -3;
        }
    // NOTE: the +nArmorShield add-back no longer feeds skill availability.
    // GetIsSkillAvailable now reads true ranks via GetSkillRank(...,TRUE).
    return (nBase-nSubtract-nModifier+nArmorShield);
    }
}

struct xAbility GetBaseAbilities(struct xAbility stat, object oPC)
{
struct xAbility base;
int iCount;
int nBaseAbility;
for(iCount = 0; iCount < 6; iCount++)//filter out the greater stat feats
    {
        switch(iCount)
        {
            case ABILITY_STRENGTH:      base.nSTR = GetBaseStat(iCount, stat.nSTR, oPC); break;
            case ABILITY_DEXTERITY:     base.nDEX = GetBaseStat(iCount, stat.nDEX, oPC); break;
            case ABILITY_CONSTITUTION:  base.nCON = GetBaseStat(iCount, stat.nCON, oPC); break;
            case ABILITY_INTELLIGENCE:  base.nINT = GetBaseStat(iCount, stat.nINT, oPC); break;
            case ABILITY_WISDOM:        base.nWIS = GetBaseStat(iCount, stat.nWIS, oPC); break;
            case ABILITY_CHARISMA:      base.nCHA = GetBaseStat(iCount, stat.nCHA, oPC); break;
        }
    }
//For skills we must still process them to remove ability and feat bonuses.
for(iCount = 0; iCount < 27; iCount++)
    {
    nBaseAbility = GetBaseSkill(iCount, stat, oPC);
    switch (iCount)
        {
            case 0: base.nANIMAL_EMPATHY = nBaseAbility; break;
            case 1: base.nCONCENTRATION = nBaseAbility; break;
            case 2: base.nDISABLE_TRAP = nBaseAbility; break;
            case 3: base.nDISCIPLINE = nBaseAbility; break;
            case 4: base.nHEAL = nBaseAbility; break;
            case 5: base.nHIDE = nBaseAbility; break;
            case 6: base.nLISTEN = nBaseAbility; break;
            case 7: base.nLORE = nBaseAbility; break;
            case 8: base.nMOVE_SILENTLY = nBaseAbility; break;
            case 9: base.nOPEN_LOCK = nBaseAbility; break;
            case 10: base.nPARRY = nBaseAbility; break;
            case 11: base.nPERFORM = nBaseAbility; break;
            case 12: base.nPERSUADE = nBaseAbility; break;
            case 13: base.nPICK_POCKET = nBaseAbility; break;
            case 14: base.nSEARCH = nBaseAbility; break;
            case 15: base.nSET_TRAP = nBaseAbility; break;
            case 16: base.nSPELLCRAFT = nBaseAbility; break;
            case 17: base.nSPOT = nBaseAbility; break;
            case 18: base.nTAUNT = nBaseAbility; break;
            case 19: base.nUSE_MAGIC_DEVICE = nBaseAbility; break;
            case 20: base.nAPPRAISE = nBaseAbility; break;
            case 21: base.nTUMBLE = nBaseAbility; break;
            case 22: base.nCRAFT_TRAP = nBaseAbility; break;
            case 23: base.nBLUFF = nBaseAbility; break;
            case 24: base.nINTIMIDATE = nBaseAbility; break;
            case 25: base.nCRAFT_ARMOR = nBaseAbility; break;
            case 26: base.nCRAFT_WEAPON = nBaseAbility; break;
        }
    }
return base;
}

void SetBaseAbilityMarkers(struct xAbility stat, object oPC)
{
SetLocalInt(oPC, "BASE_STR", stat.nSTR);
SetLocalInt(oPC, "BASE_DEX", stat.nDEX);
SetLocalInt(oPC, "BASE_CON", stat.nCON);
SetLocalInt(oPC, "BASE_INT", stat.nINT);
SetLocalInt(oPC, "BASE_WIS", stat.nWIS);
SetLocalInt(oPC, "BASE_CHA", stat.nCHA);
DoDebug(oPC, "Base ability ints set as STR: "+IntToString(GetLocalInt(oPC, "BASE_STR"))+", DEX: "+IntToString(GetLocalInt(oPC, "BASE_DEX"))+", CON: "+IntToString(GetLocalInt(oPC, "BASE_CON"))+", INT: "+IntToString(GetLocalInt(oPC, "BASE_INT"))+", WIS: "+IntToString(GetLocalInt(oPC, "BASE_WIS"))+", CHA: "+IntToString(GetLocalInt(oPC, "BASE_CHA"))+".");
SetLocalInt(oPC, "BASE_ANIMAL", stat.nANIMAL_EMPATHY);
SetLocalInt(oPC, "BASE_CONCEN", stat.nCONCENTRATION);
SetLocalInt(oPC, "BASE_DISABL", stat.nDISABLE_TRAP);
SetLocalInt(oPC, "BASE_DISCIP", stat.nDISCIPLINE);
SetLocalInt(oPC, "BASE_HEAL", stat.nHEAL);
SetLocalInt(oPC, "BASE_HIDE", stat.nHIDE);
DoDebug(oPC, "Base ability ints set as ANIMAL: "+IntToString(GetLocalInt(oPC, "BASE_ANIMAL"))+", CONCEN: "+IntToString(GetLocalInt(oPC, "BASE_CONCEN"))+", DISABL: "+IntToString(GetLocalInt(oPC, "BASE_DISABL"))+", DISCIP: "+IntToString(GetLocalInt(oPC, "BASE_DISCIP"))+", HEAL: "+IntToString(GetLocalInt(oPC, "BASE_HEAL"))+", HIDE: "+IntToString(GetLocalInt(oPC, "BASE_HIDE"))+".");
SetLocalInt(oPC, "BASE_LISTEN", stat.nLISTEN);
SetLocalInt(oPC, "BASE_LORE", stat.nLORE);
SetLocalInt(oPC, "BASE_MOVE_S", stat.nMOVE_SILENTLY);
SetLocalInt(oPC, "BASE_OPEN_L", stat.nOPEN_LOCK);
SetLocalInt(oPC, "BASE_PARRY", stat.nPARRY);
SetLocalInt(oPC, "BASE_PERFOR", stat.nPERFORM);
DoDebug(oPC, "Base ability ints set as LISTEN: "+IntToString(GetLocalInt(oPC, "BASE_LISTEN"))+", LORE: "+IntToString(GetLocalInt(oPC, "BASE_LORE"))+", MOVE_S: "+IntToString(GetLocalInt(oPC, "BASE_MOVE_S"))+", OPEN_L: "+IntToString(GetLocalInt(oPC, "BASE_OPEN_L"))+", PARRY: "+IntToString(GetLocalInt(oPC, "BASE_PARRY"))+", PERFOR: "+IntToString(GetLocalInt(oPC, "BASE_PERFOR"))+".");
SetLocalInt(oPC, "BASE_PERSUA", stat.nPERSUADE);
SetLocalInt(oPC, "BASE_PICK_P", stat.nPICK_POCKET);
SetLocalInt(oPC, "BASE_SEARCH", stat.nSEARCH);
SetLocalInt(oPC, "BASE_SET_TR", stat.nSET_TRAP);
SetLocalInt(oPC, "BASE_SPELLC", stat.nSPELLCRAFT);
SetLocalInt(oPC, "BASE_SPOT", stat.nSPOT);
DoDebug(oPC, "Base ability ints set as PERSUA: "+IntToString(GetLocalInt(oPC, "BASE_PERSUA"))+", PICK_P: "+IntToString(GetLocalInt(oPC, "BASE_PICK_P"))+", SEARCH: "+IntToString(GetLocalInt(oPC, "BASE_SEARCH"))+", SET_TR: "+IntToString(GetLocalInt(oPC, "BASE_SET_TR"))+", SPELLC: "+IntToString(GetLocalInt(oPC, "BASE_SPELLC"))+", SPOT: "+IntToString(GetLocalInt(oPC, "BASE_SPOT"))+".");
SetLocalInt(oPC, "BASE_TAUNT", stat.nTAUNT);
SetLocalInt(oPC, "BASE_USE_MA", stat.nUSE_MAGIC_DEVICE);
SetLocalInt(oPC, "BASE_APPRAI", stat.nAPPRAISE);
SetLocalInt(oPC, "BASE_TUMBLE", stat.nTUMBLE);
SetLocalInt(oPC, "BASE_CRAFT_T", stat.nCRAFT_TRAP);
SetLocalInt(oPC, "BASE_BLUFF", stat.nBLUFF);
DoDebug(oPC, "Base ability ints set as TAUNT: "+IntToString(GetLocalInt(oPC, "BASE_TAUNT"))+", USE_MA: "+IntToString(GetLocalInt(oPC, "BASE_USE_MA"))+", APPRAI: "+IntToString(GetLocalInt(oPC, "BASE_APPRAI"))+", TUMBLE: "+IntToString(GetLocalInt(oPC, "BASE_TUMBLE"))+", CRAFT_T: "+IntToString(GetLocalInt(oPC, "BASE_CRAFT_T"))+", BLUFF: "+IntToString(GetLocalInt(oPC, "BASE_BLUFF"))+".");
SetLocalInt(oPC, "BASE_INTIMI", stat.nINTIMIDATE);
SetLocalInt(oPC, "BASE_CRAFT_A", stat.nCRAFT_ARMOR);
SetLocalInt(oPC, "BASE_CRAFT_W", stat.nCRAFT_WEAPON);
DoDebug(oPC, "Base ability ints set as INTIMI: "+IntToString(GetLocalInt(oPC, "BASE_INTIMI"))+", CRAFT_A: "+IntToString(GetLocalInt(oPC, "BASE_CRAFT_A"))+", CRAFT_W: "+IntToString(GetLocalInt(oPC, "BASE_CRAFT_W"))+".");
}

void DeleteBaseAbilityMarkers(object oPC)
{
DeleteLocalInt(oPC, "BASE_STR");
DeleteLocalInt(oPC, "BASE_DEX");
DeleteLocalInt(oPC, "BASE_CON");
DeleteLocalInt(oPC, "BASE_INT");
DeleteLocalInt(oPC, "BASE_WIS");
DeleteLocalInt(oPC, "BASE_CHA");
DoDebug(oPC, "Base ability ints set as STR: "+IntToString(GetLocalInt(oPC, "BASE_STR"))+", DEX: "+IntToString(GetLocalInt(oPC, "BASE_DEX"))+", CON: "+IntToString(GetLocalInt(oPC, "BASE_CON"))+", INT: "+IntToString(GetLocalInt(oPC, "BASE_INT"))+", WIS: "+IntToString(GetLocalInt(oPC, "BASE_WIS"))+", CHA: "+IntToString(GetLocalInt(oPC, "BASE_CHA"))+".");
DeleteLocalInt(oPC, "BASE_ANIMAL");
DeleteLocalInt(oPC, "BASE_CONCEN");
DeleteLocalInt(oPC, "BASE_DISABL");
DeleteLocalInt(oPC, "BASE_DISCIP");
DeleteLocalInt(oPC, "BASE_HEAL");
DeleteLocalInt(oPC, "BASE_HIDE");
DoDebug(oPC, "Base ability ints set as ANIMAL: "+IntToString(GetLocalInt(oPC, "BASE_ANIMAL"))+", CONCEN: "+IntToString(GetLocalInt(oPC, "BASE_CONCEN"))+", DISABL: "+IntToString(GetLocalInt(oPC, "BASE_DISABL"))+", DISCIP: "+IntToString(GetLocalInt(oPC, "BASE_DISCIP"))+", HEAL: "+IntToString(GetLocalInt(oPC, "BASE_HEAL"))+", HIDE: "+IntToString(GetLocalInt(oPC, "BASE_HIDE"))+".");
DeleteLocalInt(oPC, "BASE_LISTEN");
DeleteLocalInt(oPC, "BASE_LORE");
DeleteLocalInt(oPC, "BASE_MOVE_S");
DeleteLocalInt(oPC, "BASE_OPEN_L");
DeleteLocalInt(oPC, "BASE_PARRY");
DeleteLocalInt(oPC, "BASE_PERFOR");
DoDebug(oPC, "Base ability ints set as LISTEN: "+IntToString(GetLocalInt(oPC, "BASE_LISTEN"))+", LORE: "+IntToString(GetLocalInt(oPC, "BASE_LORE"))+", MOVE_S: "+IntToString(GetLocalInt(oPC, "BASE_MOVE_S"))+", OPEN_L: "+IntToString(GetLocalInt(oPC, "BASE_OPEN_L"))+", PARRY: "+IntToString(GetLocalInt(oPC, "BASE_PARRY"))+", PERFOR: "+IntToString(GetLocalInt(oPC, "BASE_PERFOR"))+".");
DeleteLocalInt(oPC, "BASE_PERSUA");
DeleteLocalInt(oPC, "BASE_PICK_P");
DeleteLocalInt(oPC, "BASE_SEARCH");
DeleteLocalInt(oPC, "BASE_SET_TR");
DeleteLocalInt(oPC, "BASE_SPELLC");
DeleteLocalInt(oPC, "BASE_SPOT");
DoDebug(oPC, "Base ability ints set as PERSUA: "+IntToString(GetLocalInt(oPC, "BASE_PERSUA"))+", PICK_P: "+IntToString(GetLocalInt(oPC, "BASE_PICK_P"))+", SEARCH: "+IntToString(GetLocalInt(oPC, "BASE_SEARCH"))+", SET_TR: "+IntToString(GetLocalInt(oPC, "BASE_SET_TR"))+", SPELLC: "+IntToString(GetLocalInt(oPC, "BASE_SPELLC"))+", SPOT: "+IntToString(GetLocalInt(oPC, "BASE_SPOT"))+".");
DeleteLocalInt(oPC, "BASE_TAUNT");
DeleteLocalInt(oPC, "BASE_USE_MA");
DeleteLocalInt(oPC, "BASE_APPRAI");
DeleteLocalInt(oPC, "BASE_TUMBLE");
DeleteLocalInt(oPC, "BASE_CRAFT_T");
DeleteLocalInt(oPC, "BASE_BLUFF");
DoDebug(oPC, "Base ability ints set as TAUNT: "+IntToString(GetLocalInt(oPC, "BASE_TAUNT"))+", USE_MA: "+IntToString(GetLocalInt(oPC, "BASE_USE_MA"))+", APPRAI: "+IntToString(GetLocalInt(oPC, "BASE_APPRAI"))+", TUMBLE: "+IntToString(GetLocalInt(oPC, "BASE_TUMBLE"))+", CRAFT_T: "+IntToString(GetLocalInt(oPC, "BASE_CRAFT_T"))+", BLUFF: "+IntToString(GetLocalInt(oPC, "BASE_BLUFF"))+".");
DeleteLocalInt(oPC, "BASE_INTIMI");
DeleteLocalInt(oPC, "BASE_CRAFT_A");
DeleteLocalInt(oPC, "BASE_CRAFT_W");
DoDebug(oPC, "Base ability ints set as INTIMI: "+IntToString(GetLocalInt(oPC, "BASE_INTIMI"))+", CRAFT_A: "+IntToString(GetLocalInt(oPC, "BASE_CRAFT_A"))+", CRAFT_W: "+IntToString(GetLocalInt(oPC, "BASE_CRAFT_W"))+".");
}

int GetSkillPointsGainedOnLevelUp(object oPC)
{
int nClass = GetControlClass(oPC);
int nInt = GetLocalInt(oPC, "BASE_INT");
int nClassBonus = 0;
int nRaceBonus = 0;
int nTotal;
if(GetRacialType(oPC)==RACIAL_TYPE_HUMAN)
    {
    nRaceBonus = 1;
    }
switch(nClass)
    {
    case CLASS_TYPE_ROGUE:
        nClassBonus = 8; break;
    case CLASS_TYPE_SHADOWDANCER:
        nClassBonus = 6; break;
    case CLASS_TYPE_ARCANE_ARCHER:
    case CLASS_TYPE_ASSASSIN:
    case CLASS_TYPE_BARBARIAN:
    case CLASS_TYPE_BARD:
    case CLASS_TYPE_DRUID:
    case CLASS_TYPE_HARPER:
    case CLASS_TYPE_MONK:
    case CLASS_TYPE_RANGER:
    case CLASS_TYPE_SHIFTER:
        nClassBonus = 4; break;
    case CLASS_TYPE_BLACKGUARD:
    case CLASS_TYPE_CLERIC:
    case CLASS_TYPE_FIGHTER:
    case CLASS_TYPE_DIVINECHAMPION:
    case CLASS_TYPE_DRAGONDISCIPLE:
    case CLASS_TYPE_DWARVENDEFENDER:
    case CLASS_TYPE_PALADIN:
    case CLASS_TYPE_PALEMASTER:
    case CLASS_TYPE_SORCERER:
    case CLASS_TYPE_WEAPON_MASTER:
    case CLASS_TYPE_WIZARD:
        nClassBonus = 2; break;
    }
nTotal = nClassBonus+nRaceBonus+GetBaseAbilityModifier(nInt);
DoDebug(oPC, "Skill Points Gained: "+IntToString(nTotal)+".");
return nTotal;
}

int GetIsSkillAvailable(object oPC, int nSkill)
{
int nPointsAvailable = GetLocalInt(oPC, "PointsAvailable");
int nClass = GetControlClass(oPC);
int nLevel = CheckLegendaryLevel(oPC);
int nSkillMax;
// True invested ranks straight from the engine: ignores ability mods, feats and
// (critically) armor/shield check penalties, and updates live as points are added
// via HGLL_AddSkillPoint. Replaces the old BASE_* local-int markers, whose value
// for the armor-check skills (Hide/Move Silently/Parry/Pick Pocket/Set Trap/Tumble)
// was inflated by the GetBaseSkill armor add-back and pushed them over the cap.
// The menu index (nSkill) is identical to the engine SKILL_* constant.
int nSkillTotal = GetSkillRank(nSkill, oPC, TRUE);
int nSkillCost = GetCostOfSkill(nClass, nSkill);//returns -1 if not available
if (nSkillCost == 2)//cross-class
    {
    nSkillMax = (nLevel+4)/2;//they can go up to half of (three points higher than their new level), CheckLegendaryLevel returns the CURRENT level
    }
else
    {
    nSkillMax = nLevel+4;//they can go three points higher than their new level, CheckLegendaryLevel returns the CURRENT level
    }
if((nSkillCost > 0) && (nPointsAvailable >= nSkillCost) && (nSkillTotal < nSkillMax)) return TRUE;
else return FALSE;
}

string GetNameOfSkill(int nSkill)
{
string sSkill;
switch (nSkill)
    {
    case 0: sSkill = "Animal Empathy"; break;
    case 1: sSkill = "Concentration"; break;
    case 2: sSkill = "Disable Trap"; break;
    case 3: sSkill = "Discipline"; break;
    case 4: sSkill = "Heal"; break;
    case 5: sSkill = "Hide"; break;
    case 6: sSkill = "Listen"; break;
    case 7: sSkill = "Lore"; break;
    case 8: sSkill = "Move Silently"; break;
    case 9: sSkill = "Open Lock"; break;
    case 10: sSkill = "Parry"; break;
    case 11: sSkill = "Perform"; break;
    case 12: sSkill = "Persuade"; break;
    case 13: sSkill = "Pick Pocket"; break;
    case 14: sSkill = "Search"; break;
    case 15: sSkill = "Set Trap"; break;
    case 16: sSkill = "Spellcraft"; break;
    case 17: sSkill = "Spot"; break;
    case 18: sSkill = "Taunt"; break;
    case 19: sSkill = "Use Magic Device"; break;
    case 20: sSkill = "Appraise"; break;
    case 21: sSkill = "Tumble"; break;
    case 22: sSkill = "Craft Trap"; break;
    case 23: sSkill = "Bluff"; break;
    case 24: sSkill = "Intimidate"; break;
    case 25: sSkill = "Craft Armor"; break;
    case 26: sSkill = "Craft Weapon"; break;
    default: sSkill = ""; break;
    }
return sSkill;
}

string GetNameOfTrackingInt(int nSkill)
{
string sSkill;
switch (nSkill)
    {
    case 0: sSkill = "BASE_ANIMAL"; break;
    case 1: sSkill = "BASE_CONCEN"; break;
    case 2: sSkill = "BASE_DISABL"; break;
    case 3: sSkill = "BASE_DISCIP"; break;
    case 4: sSkill = "BASE_HEAL"; break;
    case 5: sSkill = "BASE_HIDE"; break;
    case 6: sSkill = "BASE_LISTEN"; break;
    case 7: sSkill = "BASE_LORE"; break;
    case 8: sSkill = "BASE_MOVE_S"; break;
    case 9: sSkill = "BASE_OPEN_L"; break;
    case 10: sSkill = "BASE_PARRY"; break;
    case 11: sSkill = "BASE_PERFOR"; break;
    case 12: sSkill = "BASE_PERSUA"; break;
    case 13: sSkill = "BASE_PICK_P"; break;
    case 14: sSkill = "BASE_SEARCH"; break;
    case 15: sSkill = "BASE_SET_TR"; break;
    case 16: sSkill = "BASE_SPELLC"; break;
    case 17: sSkill = "BASE_SPOT"; break;
    case 18: sSkill = "BASE_TAUNT"; break;
    case 19: sSkill = "BASE_USE_MA"; break;
    case 20: sSkill = "BASE_APPRAI"; break;
    case 21: sSkill = "BASE_TUMBLE"; break;
    case 22: sSkill = "BASE_CRAFT_T"; break;
    case 23: sSkill = "BASE_BLUFF"; break;
    case 24: sSkill = "BASE_INTIMI"; break;
    case 25: sSkill = "BASE_CRAFT_A"; break;
    case 26: sSkill = "BASE_CRAFT_W"; break;
    default: sSkill = ""; break;
    }
return sSkill;
}

int GetHitPointsGainedOnLevelUp(object oPC)
{
int nClass = GetControlClass(oPC);
int nCon = GetLocalInt(oPC, "BASE_CON");
int nClassDie;
int nFeatBonus = 0;
int nTotal;
if(GetHasFeat(FEAT_TOUGHNESS, oPC))
{
nFeatBonus = 1;
}
switch(nClass)
    {
    case CLASS_TYPE_DWARVENDEFENDER:
    case CLASS_TYPE_BARBARIAN:
        nClassDie = 12; break;
    case CLASS_TYPE_DIVINECHAMPION:
    case CLASS_TYPE_WEAPON_MASTER:
    case CLASS_TYPE_PALADIN:
    case CLASS_TYPE_RANGER:
    case CLASS_TYPE_BLACKGUARD:
    case CLASS_TYPE_FIGHTER:
    case CLASS_TYPE_DRAGONDISCIPLE:
        nClassDie = 10; break;
    case CLASS_TYPE_SHADOWDANCER:
    case CLASS_TYPE_DRUID:
    case CLASS_TYPE_ARCANE_ARCHER:
    case CLASS_TYPE_MONK:
    case CLASS_TYPE_SHIFTER:
    case CLASS_TYPE_CLERIC:
        nClassDie = 8; break;
    case CLASS_TYPE_ROGUE:
    case CLASS_TYPE_ASSASSIN:
    case CLASS_TYPE_BARD:
    case CLASS_TYPE_HARPER:
    case CLASS_TYPE_PALEMASTER:
        nClassDie = 6; break;
    case CLASS_TYPE_SORCERER:
    case CLASS_TYPE_WIZARD:
        nClassDie = 4; break;
    }
nTotal = nClassDie+nFeatBonus+GetBaseAbilityModifier(nCon);
DoDebug(oPC, "HP Gained: "+IntToString(nTotal)+".");
return nTotal;
}

void ReplenishLimitedUseFeats(object oPC)
{
int nFeat = 0;
for(nFeat = 0; nFeat < 1072; nFeat++)
    {
    if (GetIsFeatLimitedUses(nFeat))
        {
        IncrementRemainingFeatUses(oPC, nFeat);
        }
    }
}

int GetIsFeatAvailable(int nFeat, object oPC)
{
int nClass = GetControlClass(oPC);
if (DEV_CRIT_DISABLED && GetIsFeatDevCrit(nFeat)) return FALSE;
if (GetIsFeatFirstLevelOnly(nFeat)) return FALSE;
if (GetHasFeat(nFeat, oPC) && nFeat != 13) return FALSE;//only Extra Turning (13) may be taken multiple times
if (!GetIsClassFeat(nFeat, nClass, oPC) && !GetIsGeneralFeat(nFeat)) return FALSE;//if it's not a class skill and it's not a general skill return FALSE
if (GetAreFeatStatReqsMet(nFeat, oPC) &&
    GetAreFeatSkillReqsMet(nFeat, oPC) &&
    GetAreFeatFeatReqsMet(nFeat, oPC) &&
    GetHasRequiredSpellLevelForFeat(oPC, nFeat)) return TRUE;

return FALSE;
}

string GetNameOfAbility(int nStat)
{
string sReturn;
switch (nStat)
    {
    case ABILITY_STRENGTH: sReturn = "Strength"; break;
    case ABILITY_DEXTERITY: sReturn = "Dexterity"; break;
    case ABILITY_CONSTITUTION: sReturn = "Constitution"; break;
    case ABILITY_INTELLIGENCE: sReturn = "Intelligence"; break;
    case ABILITY_WISDOM: sReturn = "Wisdom"; break;
    case ABILITY_CHARISMA: sReturn = "Charisma"; break;
    }
return sReturn;
}

string GetNameOfClass(int nClass)
{
// classes.2da "Name" column holds a StrRef; resolve it through the TLK so CEP /
// custom class names come out correct. Falls back to "Unknown" for invalid rows.
string sStrRef = Get2DAString("classes", "Name", nClass);
if (sStrRef == "") return "Unknown";
string sName = GetStringByStrRef(StringToInt(sStrRef));
if (sName == "") return "Unknown";
return sName;
}

int GetIsClassFeat(int nFeat, int nClass, object oPC)
{
int nLevel = GetClassLevelReqForFeat(nFeat, nClass);
if (nLevel < -1) return FALSE;
if (GetLevelByClass(nClass, oPC) < nLevel) return FALSE;
return TRUE;
}

//below used to compile
/*
void main()
{

}
*/
