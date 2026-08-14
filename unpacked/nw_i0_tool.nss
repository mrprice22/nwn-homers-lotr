//::///////////////////////////////////////////////
//::
//:: Tools Include File
//::
//:: NW_I0_TOOL.nss
//::
//:: Copyright (c) 2002 Bioware Corp.
//::
//::
//:://////////////////////////////////////////////
//::
//:: Created By: Neil Flynn with code from
//::             Brent Knowles
//:: Created On: February 12, 2001
//::
//:://////////////////////////////////////////////

// Premium 2x boost (merit redemptions 201-204): RewardPartyGP multiplies quest
// GOLD via Boost_GiveGold for players with an active boost. (Quest XP is doubled
// centrally by the NWNX SetExperience handler boost_xp_evt, not here.) Bank
// withdrawals and item sales do NOT route through here, so they stay un-boosted.
#include "boost_inc"

int DC_EASY = 0;
int DC_MEDIUM = 1;
int DC_HARD = 2;
// * this is used by some of the template scripts
// * 100 - this number is the chance of that dialog
// * appearing
int G_CLASSCHANCE = 70;

//::///////////////////////////////////////////////
//:: HasItem
//:: Copyright (c) 2002 Bioware Corp.
//:://////////////////////////////////////////////
/*
      A wrapper to simplify checking for an item.
*/
//:://////////////////////////////////////////////
//:: Created By:        Brent
//:: Created On:        November 2001
//:://////////////////////////////////////////////

int HasItem(object oCreature, string s)
{
    return  GetIsObjectValid(GetItemPossessedBy(oCreature, s));
}

//::///////////////////////////////////////////////
//:: Take Gold
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    Takes nAmount of gold from the object speaking.
    By default, the gold is destroyed.
*/
//:://////////////////////////////////////////////
//:: Created By: Brent
//:: Created On: November 2001
//:://////////////////////////////////////////////
void TakeGold(int nAmount, object oGoldHolder, int bDestroy=TRUE)
{
    TakeGoldFromCreature(nAmount, oGoldHolder, bDestroy);
}


//::///////////////////////////////////////////////
//:: HasGold
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    Checks to see if the player has nAmount of gold
*/
//:://////////////////////////////////////////////
//:: Created By:
//:: Created On:
//:://////////////////////////////////////////////
int HasGold(int nAmount, object oGoldHolder)
{
    return GetGold(oGoldHolder) >= nAmount;
}

///////////////////////////////////////////////////////////////////////////////
//
//  AutoDC
//
///////////////////////////////////////////////////////////////////////////////
//  Returns a pass value based on the object's level and the suggested DC
// December 20 2001: Changed so that the difficulty is determined by the
// NPC's Hit Dice
///////////////////////////////////////////////////////////////////////////////
//  Created By: Brent, September 13 2001
///////////////////////////////////////////////////////////////////////////////
int AutoDC(int DC, int nSkill, object oTarget)
{
    /*
    Easy = Lvl/4 ...rounded up
    Moderate = 3/Lvl + Lvl ...rounded up
    Difficult = Lvl * 1.5 + 6 ...rounded up
    */
    int nLevel = GetHitDice(OBJECT_SELF);
    int nTest = 0;
    switch (DC)
    {
    case 0: nTest = nLevel / 4 + 1; break;
        // * minor tweak to lower the values a little
    case 1: nTest = (3 / nLevel + nLevel) - abs( (nLevel/2) -2); break;
    case 2: nTest = FloatToInt(nLevel * 1.5 + 6) - abs( ( FloatToInt(nLevel/1.5) -2));   break;
    }
    if (GetSkillRank(nSkill, oTarget) >= nTest)
    {
       return TRUE;
    }
       return FALSE;
}

//::///////////////////////////////////////////////
//:: DoGiveXP
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
      Gives the designated XP to the object
      using the design rules for XP
      distribution.
*/
//:://////////////////////////////////////////////
//:: Created By:
//:: Created On:
//:://////////////////////////////////////////////

void DoGiveXP(string sJournalTag, int nPercentage, object oTarget, int QuestAlignment=ALIGNMENT_NEUTRAL)
{

    float nRewardMod = 1.0;
    // * error handling
    if ((nPercentage < 0) || (nPercentage > 100))
    {
        nPercentage = 100;
    }
    float nXP = GetJournalQuestExperience(sJournalTag) * (nPercentage * 0.01);

    // * for each party member
    // * cycle through them and
    // * and give them the appropriate reward
    // * HACK FOR NOW
    if ((GetAlignmentGoodEvil(oTarget) == ALIGNMENT_NEUTRAL) || (QuestAlignment ==ALIGNMENT_NEUTRAL) )
    {
        nRewardMod = 1.0;
    }
    else
    if (GetAlignmentGoodEvil(oTarget) == QuestAlignment)
    {
        nRewardMod = 1.25;
    }
    else
    if (GetAlignmentGoodEvil(oTarget) != QuestAlignment)
    {
        nRewardMod = 0.75;
    }

    // xp_script marks this as a deliberate script grant so the kill cap in
    // boost_xp_evt.nss leaves it alone -- a computed quest reward could otherwise
    // land inside the engine-award window and be silently clamped to 6,000.
    SetLocalInt(oTarget, "xp_script", 1);
    GiveXPToCreature(oTarget, FloatToInt(nRewardMod * nXP));
    DeleteLocalInt(oTarget, "xp_script");
}


///////////////////////////////////////////////////////////////////////////////
//
//  RewardPartyGP
//
///////////////////////////////////////////////////////////////////////////////
//  Gives the GP to (if bAllParty = TRUE) all party members.
//  Each players gets the GP value amount.
///////////////////////////////////////////////////////////////////////////////
//  Created By: Brent, September 13, 2001
///////////////////////////////////////////////////////////////////////////////

void RewardPartyGP(int GP, object oTarget,int bAllParty=TRUE)
{
    // * for each party member
    // * cycle through them and
    // * and give them the appropriate reward
    // * HACK FOR NOW
    if (bAllParty == TRUE)
    {
        object oPartyMember = GetFirstFactionMember(oTarget, TRUE);
        while (GetIsObjectValid(oPartyMember) == TRUE)
        {
            //AssignCommand(oPartyMember, SpeakString("MY GP reward is: " + IntToString(GP)));
            Boost_GiveGold(oPartyMember, GP);
            oPartyMember = GetNextFactionMember(oTarget, TRUE);
        }
    }
    else
    {
     Boost_GiveGold(oTarget, GP);
    }
}

///////////////////////////////////////////////////////////////////////////////
//
//  RewardPartyXP
//
///////////////////////////////////////////////////////////////////////////////
//  Gives the GP to (if bAllParty = TRUE) all party members.
//  Each players gets the GP value amount.
///////////////////////////////////////////////////////////////////////////////
//  Created By: Brent, September 13, 2001
///////////////////////////////////////////////////////////////////////////////

void RewardPartyXP(int XP, object oTarget,int bAllParty=TRUE)
{
    // * for each party member
    // * cycle through them and
    // * and give them the appropriate reward
    // * HACK FOR NOW
    // xp_script: deliberate script grant, exempt from the engine kill cap in
    // boost_xp_evt.nss (see DoGiveXP above).
    if (bAllParty == TRUE)
    {
        object oPartyMember = GetFirstFactionMember(oTarget, TRUE);
        while (GetIsObjectValid(oPartyMember) == TRUE)
        {
            SetLocalInt(oPartyMember, "xp_script", 1);
            GiveXPToCreature(oPartyMember, XP);
            DeleteLocalInt(oPartyMember, "xp_script");
            oPartyMember = GetNextFactionMember(oTarget, TRUE);
        }
    }
    else
    {
     SetLocalInt(oTarget, "xp_script", 1);
     GiveXPToCreature(oTarget, XP);
     DeleteLocalInt(oTarget, "xp_script");
    }
}

///////////////////////////////////////////////////////////////////////////////
//
//  CheckPartyForItem
//
///////////////////////////////////////////////////////////////////////////////
//  Checks everyone in the party for an item
///////////////////////////////////////////////////////////////////////////////
//  Created By: Brent, September 13, 2001
///////////////////////////////////////////////////////////////////////////////

int CheckPartyForItem(object oMember, string sItem)
{
    object oPartyMember = GetFirstFactionMember(oMember, TRUE);
    while (GetIsObjectValid(oPartyMember) == TRUE)
    {
        if(HasItem(oPartyMember, sItem))
            return TRUE;
        oPartyMember = GetNextFactionMember(oMember, TRUE);
    }

    return FALSE;
}

int CheckPlayerForItem(object oMember, string sItem)
{
          if(HasItem(oMember, sItem))
          {
            return TRUE;
            }

    return FALSE;
}
