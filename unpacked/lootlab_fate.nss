// lootlab_fate.nss - Loot Lab: put one Shard of Fate in the admin's pack
// (Phase 7, lo-fate-token) to test the anvil reforge and the boss bonus roll.
// Loot Lab action (emotewand.dlg Entry 19). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    object oShard = CreateItemOnObject(LOOTD_FATE_RESREF, oPC);
    if (!GetIsObjectValid(oShard))
    {
        SendMessageToPC(oPC, "LOOT: Shard of Fate blueprint '" + LOOTD_FATE_RESREF
            + "' could not be created.");
        return;
    }
    SendMessageToPC(oPC, "Loot Lab: a Shard of Fate is in your pack. Boss bonus rolls: "
        + "prompt " + IntToString(LOOTD_FATE_TIMEOUT) + "s, lockout "
        + IntToString(LOOTD_FATE_LOCKOUT / 3600) + "h per boss, profile '"
        + LOOTD_FATE_PROFILE + "'; boss drop chance " + IntToString(LOOTD_FATE_BOSS_CHANCE)
        + "/1000.");
}
