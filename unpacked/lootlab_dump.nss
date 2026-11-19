// lootlab_dump.nss - Loot Lab: for every rolled, augmented (lo-augment-originals)
// or socketed item in the admin's pack, print its LOOT_* stamps, its engine value against its rarity's budget,
// and its sockets and gem-touched properties (Phase 5).
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
        int nSock = GetLocalInt(oItem, "SOCKET_MAX");
        int bAug = GetLocalInt(oItem, "LOOT_AUG");
        if (Loot_IsRolled(oItem) || nSock > 0 || bAug)
        {
            string s = Loot_IsRolled(oItem) ? Loot_Describe(oItem)
                     : GetName(oItem) + (bAug ? " [augmented]" : " [not rolled]") + " sockets "
                       + IntToString(GetLocalInt(oItem, "SOCKET_FILLED")) + "/" + IntToString(nSock);
            // lo-augment-originals: the augment's stamps and its value now.
            if (bAug)
            {
                s += "\n   augment: " + LootD_RarityName(GetLocalInt(oItem, "LOOT_RARITY"))
                   + " L" + IntToString(GetLocalInt(oItem, "LOOT_LVL"))
                   + " from " + GetLocalString(oItem, "LOOT_PROFILE")
                   + ", value now " + ForgeGold(ForgeItemValue(oItem, TRUE)) + " gp";
                int k;
                for (k = 0; k < GetLocalInt(oItem, "LOOT_AUG_UP_N"); k++)
                    s += "\n   raised to " + GetLocalString(oItem, "LOOT_AUG_UP_" + IntToString(k));
                for (k = 0; k < GetLocalInt(oItem, "LOOT_AFX_N"); k++)
                    s += "\n   added " + GetLocalString(oItem, "LOOT_AFX_" + IntToString(k));
            }
            // Phase 5: the gems set in it and every property a gem has touched.
            int i;
            for (i = 0; i < GetLocalInt(oItem, "SOCKET_FILLED"); i++)
                s += "\n   socket " + IntToString(i) + ": "
                   + GetLocalString(oItem, "SOCKET_" + IntToString(i) + "_GEM");
            for (i = 0; i < GetLocalInt(oItem, "GEM_P_N"); i++)
                s += "\n   gem prop " + GetLocalString(oItem, "GEM_P_" + IntToString(i))
                   + (GetLocalInt(oItem, "GEM_P_" + IntToString(i) + "_OWN") ? " (created)" : " (raised)");
            SendMessageToPC(oPC, s);
            nFound++;
        }
        oItem = GetNextItemInInventory(oPC);
    }
    SendMessageToPC(oPC, "Loot Lab: " + IntToString(nFound) + " rolled, augmented or socketed item(s) in your pack.");
}
