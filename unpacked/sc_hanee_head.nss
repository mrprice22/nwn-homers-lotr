//::///////////////////////////////////////////////
//:: FileName sc_hanee_head
//:://////////////////////////////////////////////
/*
    Hanee the Loon (Bree) - head-reaction branch gate.
    Fires when the PC returns carrying Azagoth's Head
    and has not yet collected the intermediate reward.
    (roadmap: gondor-scribe)
*/
//:://////////////////////////////////////////////
#include "nw_i0_tool"

int StartingConditional()
{
    object oPC = GetPCSpeaker();

    // Must be carrying Azagoth's Head
    if(!CheckPlayerForItem(oPC, "azagothshead"))
        return FALSE;

    // One-time reward - Hanee does not take the head, so gate on a flag
    if(GetLocalInt(oPC, "hanee_head_reward"))
        return FALSE;

    return TRUE;
}
