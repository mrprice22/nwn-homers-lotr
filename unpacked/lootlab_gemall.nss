// lootlab_gemall.nss - Loot Lab: grant one gem of every family at the menu's
// rarity floor, into the admin's pack.
// Roadmap: Socket-system-for-weapons. Loot Lab action (emotewand.dlg Entry 19,
// Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"
#include "gem_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    int nTier = LL_Floor(oPC);
    int n = 0;
    int i;
    for (i = 0; i < LOOTD_GEMFAM_COUNT; i++)
        if (GetIsObjectValid(Gem_Create(i, nTier, oPC))) n++;
    SendMessageToPC(oPC, "Loot Lab: granted " + IntToString(n) + " " + LootD_RarityName(nTier)
        + " gem(s), one of each family.");
}
