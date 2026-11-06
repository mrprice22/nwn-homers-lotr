// lootlab_gem1.nss - Loot Lab: grant one random socket gem at the menu's rarity
// floor (the gem's tier IS the floor - no roll), into the admin's pack.
// Roadmap: Socket-system-for-weapons. Loot Lab action (emotewand.dlg Entry 19,
// Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"
#include "gem_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    object oGem = Gem_Create(Gem_PickFamily(), LL_Floor(oPC), oPC);
    if (GetIsObjectValid(oGem))
        SendMessageToPC(oPC, "Loot Lab: granted " + GetName(oGem) + " (" + GetResRef(oGem) + ").");
}
