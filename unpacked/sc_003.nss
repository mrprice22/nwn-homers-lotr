//::///////////////////////////////////////////////
//:: FileName sc_003
//:://////////////////////////////////////////////
//:: Gondor Scribe -- TRUE while this character is carrying Azagoth's head AND
//:: has not already been paid for it. Gates the turn-in entry (at_008).
//::
//:: The !WOS_Done half matters because Azagoth respawns: without it, a second
//:: head would re-open the 10,000 XP node forever.
//:://////////////////////////////////////////////
#include "nw_i0_tool"
#include "wos_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();

    if (WOS_Done(oPC))                              return FALSE;
    if (!CheckPlayerForItem(oPC, "azagothshead"))   return FALSE;

    return TRUE;
}
