//::///////////////////////////////////////////////
//:: FileName sc_wos_busy
//:://////////////////////////////////////////////
//:: Gondor Scribe -- TRUE while this character has the Well of Souls quest in
//:: hand but has not finished it. Gates the short reminder + portal directions.
//::
//:: Deliberately not the full briefing: replaying that is what let the quest be
//:: accepted over and over. Note the node this gates writes NO journal entry,
//:: so a returning player's journal cannot be rewound to entry 1.
//:://////////////////////////////////////////////
#include "wos_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return WOS_Accepted(oPC) && !WOS_Done(oPC);
}
