// lootlab_dump.nss - Loot Lab: for every rolled item in the admin's pack, print
// its LOOT_* stamps and its engine value against its rarity's budget.
// Roadmap: lo-loot-core. Loot Lab action (emotewand.dlg Entry 19, Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    int nFound = 0;
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (Loot_IsRolled(oItem))
        {
            SendMessageToPC(oPC, Loot_Describe(oItem));
            nFound++;
        }
        oItem = GetNextItemInInventory(oPC);
    }
    SendMessageToPC(oPC, "Loot Lab: " + IntToString(nFound) + " rolled item(s) in your pack.");
}
