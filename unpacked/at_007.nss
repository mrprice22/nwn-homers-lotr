//::///////////////////////////////////////////////
//:: FileName at_007
//:://////////////////////////////////////////////
//:: Gondor Scribe -- quest accept: hand over the Annuminas Key.
//:: The key opens the warded Annuminas chests (KeyRequired + AutoRemoveKey),
//:: which self-destroy the key on use, so one key opens only one warded chest.
//::
//:: Anti-farm: the "already granted" flag is PERSISTENT (questcddb campaign
//:: DB, row uuid+quest via quest_cd_inc), not a session local int, so logging
//:: out and back in no longer earns a second key. sc_annukey.nss reads the
//:: same stamp so the scribe stops offering the key at all once it is spent.
//:://////////////////////////////////////////////
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();

    // Ever granted on this character? (persists across relogs and reboots)
    if (QCD_LastStamp(oPC, "annu_key") != 0)
        return;
    if (GetIsObjectValid(GetItemPossessedBy(oPC, "AnnuminasKey")))
        return;

    CreateItemOnObject("annuminaskey", oPC, 1);
    QCD_Stamp(oPC, "annu_key");
}
