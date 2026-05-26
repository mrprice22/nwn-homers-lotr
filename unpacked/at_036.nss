//::///////////////////////////////////////////////
//:: FileName at_036
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 10/12/2002 10:41:54 PM
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();

    // Anti-exploit: player can drop the proof item mid-conversation to keep it.
    object oItemToTake = GetItemPossessedBy(oPC, "NW_WPLMSC004");
    if (!GetIsObjectValid(oItemToTake))
    {
        FloatingTextStringOnCreature(
            "You must have the proof in your possession.", oPC, FALSE);
        return;
    }

    DestroyObject(oItemToTake);
    RewardPartyGP(10000, oPC);
    RewardPartyXP(2000, oPC);
}
