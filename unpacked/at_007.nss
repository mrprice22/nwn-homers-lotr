//::///////////////////////////////////////////////
//:: FileName at_007
//:://////////////////////////////////////////////
//:: Gondor Scribe -- quest ACCEPT ("Alright, where is this portal?").
//::
//:: This node used to hand over the Annuminas Key. It no longer does: the key
//:: is a completion reward now, granted by at_008 when Azagoth's head is turned
//:: in. Giving it at accept -- before the player had done anything -- is what
//:: made re-accepting the quest worth farming.
//::
//:: All this does now is record the stage. WOS_Accept stamps questcddb and
//:: writes journal "The Well of Souls" entry 1 in one call, and is a no-op if
//:: the character has already accepted or already finished.
//:://////////////////////////////////////////////
#include "wos_inc"

void main()
{
    WOS_Accept(GetPCSpeaker());
}
