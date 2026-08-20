//::///////////////////////////////////////////////
//:: FileName sc_hanee_head
//:://////////////////////////////////////////////
/*
    Hanee the Loon (Bree) - head-reaction branch gate.
    Fires when the PC returns carrying Azagoth's Head
    and has not yet collected the intermediate reward.
    (roadmap: gondor-scribe)

    The "already paid" flag is the questcddb stamp
    "hanee_head", not a session local - Hanee does not
    take the head, so a forgetful gate meant a relog
    bought another 5,000 XP off the same trophy.
*/
//:://////////////////////////////////////////////
#include "nw_i0_tool"
#include "quest_cd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();

    // Must be carrying Azagoth's Head
    if(!CheckPlayerForItem(oPC, "azagothshead"))
        return FALSE;

    // One-time reward - persists across relogs and reboots
    if(QCD_LastStamp(oPC, "hanee_head") != 0)
        return FALSE;

    return TRUE;
}
