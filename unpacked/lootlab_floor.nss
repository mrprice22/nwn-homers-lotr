// lootlab_floor.nss - Loot Lab: cycle the rarity floor Common -> ... -> Legendary -> Common.
// Roadmap: lo-loot-core. Loot Lab action (emotewand.dlg Entry 19, Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    SetLocalInt(oPC, "LOOTLAB_FLOOR", (LL_Floor(oPC) + 1) % LOOTD_RARITY_COUNT);
    LL_SetTokens(oPC);
}
