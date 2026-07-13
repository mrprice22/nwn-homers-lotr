#include "zdlg_include_i"
#include "hgll_func_inc"
// This script fires off the leveling conversation, if the PC meets certain requirements.
// It goes onused of a placeable.
void main()
{
    object oPC = GetLastUsedBy();
    /////////////Check for and remove all skill and feat adding gear. This is necessary becase adding and subtracting 50 (the max bonus) to the skill will cause errors when the toal skill plus stat bonuses plus the 50 exceed the field cap of 127, and because it is impossible to distinguish between feats on the character and feats on their gear.
    int nSkFtItemCheck = 0;
    int iCount;
    object oItem;
    for(iCount = 0; iCount < NUM_INVENTORY_SLOTS; iCount++)
        {
        oItem = GetItemInSlot(iCount, oPC);
        if(GetItemHasItemProperty(oItem, ITEM_PROPERTY_SKILL_BONUS) || GetItemHasItemProperty(oItem, ITEM_PROPERTY_BONUS_FEAT))
            {
            AssignCommand(oPC, ActionUnequipItem(oItem));
            nSkFtItemCheck = 1;
            }
        }
    if (nSkFtItemCheck == 1)
        {
        SendMessageToPC(oPC, "You were stripped of all gear with skill or feat bonuses. Please use the leveler again.");
        return;
        }
    /////////////

    ExportSingleCharacter(oPC);//save the character here for future Leto edits
    ReplenishLimitedUseFeats(oPC);
    int nCheck = GetHasXPForNextLL(oPC);
    struct xAbility ability;
    struct xAbility base;
    string sXPNeeded;
    int nCClass;
    int nSkillPoints;
        switch (nCheck)
        {
        case -2: SendMessageToPC(oPC, "You are already level 60, and cannot advance any further."); break;
        case -1: SendMessageToPC(oPC, "You must be level 40 to gain legendary levels."); break;
        case 0:
            sXPNeeded = IntToString(GetXPNeededForNextLL(oPC));
            DoDebug(oPC, "GetXPNeededForNextLL returned "+sXPNeeded);
            SendMessageToPC(oPC, "You still need " + sXPNeeded + " experience points before you can gain another level.");
            break;
        case 1:
            if (GetCanGainLL(oPC))//covers any conditions you add other than level and experience
                {                 //by default this always returns TRUE, you may set additional conditions
            ////////Drop any staged picks left behind by an interrupted level-up////////
                //these are PC locals, so a disconnect part-way through the conversation
                //carries them into the .bic; committing them next session would hand out
                //picks the player never confirmed. Must run before PointsAvailable is seeded.
                HGLL_ClearPendingPicks(oPC);
            ////////Check Abilities and Set Local Ints to track them////////
                ability = GetRoughAbilities(oPC);//Pull up info on base skills and stats
                base = GetBaseAbilities(ability, oPC);//Process that data further to get base skills and base stats
                SetBaseAbilityMarkers(base, oPC);//Set local ints for the 6 ability scores and 27 skills
            ////////Check/Set Control Class////////
                nCClass = NWNX_Object_GetInt(oPC, "hgll_control_class");//We use a persistant int so it can be accessed anytime, like with PC Scrye etc. It is NOT checked during the conversation.
                if (nCClass == 0)//not set or Barbarian is the CC
                    {
                    nCClass = GetControlClass(oPC);
                    SetControlClass(oPC, nCClass);
                    }
            ////////Check Skill Points Gained and Set Local Int to track them////////
                nSkillPoints = NWNX_Object_GetInt(oPC, "hgll_points_avail");//points saved from last LL, if any - non-LL points not tracked
                nSkillPoints += GetSkillPointsGainedOnLevelUp(oPC);
                SetLocalInt(oPC, "PointsAvailable", nSkillPoints);
            ////////Declare Tracking Variables////////
                SetLocalString(oPC, "LetoscriptLL", "");//String to track Letoscript changes to be made
                SetLocalString(oPC, "TrackChanges", "");//String to track description of changes to be made
            ////// Start up the conversation between ourselves and////////
                // the clicking player.  We make the conversation
                // private since it's really a menu selection and
                // not a real conversation.  We also don't want it to
                // play a hello.
                StartDlg( oPC, OBJECT_SELF, "hgll_dlg_leveler", TRUE, FALSE );
                }
            else
                {
                //explain why the conditions other than level and experience failed
                SendMessageToPC(oPC, "You must be immortal to gain legendary levels.");
                }
            break;
        }
    DoDebug(oPC, "GetHasXPForNextLL returned "+IntToString(nCheck));
}
