// lootlab_fateclr.nss - Loot Lab: clear the admin's own Shard of Fate bonus-roll
// lockouts (lootdb loot_fate_lockout), so the boss bonus roll can be tested more
// than once a day (Phase 7, lo-fate-token). Loot Lab action (emotewand.dlg
// Entry 19). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    int n = Loot_FateClear(oPC);
    SendMessageToPC(oPC, "Loot Lab: cleared " + IntToString(n)
        + " Shard of Fate lockout(s) for this character.");
}
