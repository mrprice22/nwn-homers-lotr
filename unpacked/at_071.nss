//::///////////////////////////////////////////////
//:: FileName at_071
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 11/11/2002 10:58:05 AM
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();

    // at_kashan04 sets this flag only if it successfully took the Troyspin item.
    if (!GetLocalInt(oPC, "kashan_gave_item"))
    {
        FloatingTextStringOnCreature(
            "You must bring proof of what happened to complete this.", oPC, FALSE);
        return;
    }
    DeleteLocalInt(oPC, "kashan_gave_item");

    RewardPartyGP(200, oPC);
    RewardPartyXP(250, oPC);
    CreateItemOnObject("ringofwoe", oPC, 1);
}
