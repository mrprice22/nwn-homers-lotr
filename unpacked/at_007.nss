//::///////////////////////////////////////////////
//:: FileName at_007
//:://////////////////////////////////////////////
//:: Gondor Scribe -- quest accept: hand over the Annuminas Key.
//:: The key opens the warded Annuminas chests (KeyRequired + AutoRemoveKey),
//:: which self-destroy the key on use, so one key opens only one warded chest.
//:: Guard against stockpiling: give at most one key per login, and never a
//:: second while one is already held.
//:://////////////////////////////////////////////
void main()
{
    object oPC = GetPCSpeaker();

    if (GetLocalInt(oPC, "annu_key_given"))
        return;
    if (GetIsObjectValid(GetItemPossessedBy(oPC, "AnnuminasKey")))
        return;

    CreateItemOnObject("annuminaskey", oPC, 1);
    SetLocalInt(oPC, "annu_key_given", 1);
}
