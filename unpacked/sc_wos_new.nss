//::///////////////////////////////////////////////
//:: FileName sc_wos_new
//:://////////////////////////////////////////////
//:: Gondor Scribe -- TRUE only for a character who has never taken the Well of
//:: Souls quest. Gates the full briefing chain.
//::
//:: This is the fix for the re-accept loop: the briefing used to be the
//:: unconditional fallback of the scribe's StartingList, so it replayed on
//:: every conversation forever. It is now reachable exactly once per character.
//:://////////////////////////////////////////////
#include "wos_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return !WOS_Accepted(oPC) && !WOS_Done(oPC);
}
