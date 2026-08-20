//::///////////////////////////////////////////////
//:: FileName at_013
//:://////////////////////////////////////////////
//:: Gondor Scribe -- the player signs off after the turn-in.
//::
//:: Used to be SetLocalInt(oPC, "azagothdead", 1) -- a session local, so the
//:: "you have already done this" greeting vanished on relog and the whole
//:: briefing chain became available again. Now it advances the persistent
//:: stage instead; WOS_Complete is idempotent, so reaching this after at_008
//:: has already run costs nothing.
//:://////////////////////////////////////////////
#include "wos_inc"

void main()
{
    WOS_Complete(GetPCSpeaker());
}
