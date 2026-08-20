//::///////////////////////////////////////////////
//:: FileName sc_annukey
//:://////////////////////////////////////////////
//:: Gondor Scribe -- TRUE when this character has finished the quest but has
//:: never been given the Annuminas Key. Gates the "claim your key" entry
//:: (at_007_key).
//::
//:: This is the grandfather path. The key used to come at quest accept; it now
//:: comes with the head turn-in, and the head is consumed, so anyone who
//:: finished before the change has no way back to the reward node. They get one
//:: chance here, and the annu_key stamp closes it behind them.
//::
//:: The stamp lives in the questcddb campaign DB (quest_cd row ident+"annu_key")
//:: so it survives logout and server reboots.
//:://////////////////////////////////////////////
#include "wos_inc"

int StartingConditional()
{
    return WOS_CanClaimKey(GetPCSpeaker());
}
