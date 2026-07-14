//::///////////////////////////////////////////////
//:: FileName at_008
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/21/2002 11:50:49 AM
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
    // Give the speaker some XP
    RewardPartyXP(10000, GetPCSpeaker());


    // Remove items from the player's inventory
    object oItemToTake;
    oItemToTake = GetItemPossessedBy(GetPCSpeaker(), "azagothshead");
    if(GetIsObjectValid(oItemToTake) != 0)
        DestroyObject(oItemToTake);
}
