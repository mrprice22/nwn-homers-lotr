//::///////////////////////////////////////////////
//:: FileName sc_annukey
//:://////////////////////////////////////////////
//:: Gondor Scribe -- TRUE while this character has never been given the
//:: Annuminas Key. Gates the "here is the key" accept entry in
//:: gondorscribe.dlg so a relog cannot buy a second key; the fallback entry
//:: right below it repeats the directions without the key.
//::
//:: The stamp lives in the questcddb campaign DB (quest_cd row uuid+"annu_key",
//:: written by at_007.nss), so it survives logout and server reboots.
//:://////////////////////////////////////////////
#include "quest_cd_inc"

int StartingConditional()
{
    return (QCD_LastStamp(GetPCSpeaker(), "annu_key") == 0);
}
