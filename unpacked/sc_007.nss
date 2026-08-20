//::///////////////////////////////////////////////
//:: FileName sc_007
//:://////////////////////////////////////////////
//:: Gondor Scribe -- TRUE once this character has turned in Azagoth's head.
//:: Gates the post-completion greeting.
//::
//:: Was GetLocalInt(oPC, "azagothdead") -- session-scoped, so it forgot on
//:: relog. Now reads the persistent stage (questcddb).
//:://////////////////////////////////////////////
#include "wos_inc"

int StartingConditional()
{
    return WOS_Done(GetPCSpeaker());
}
