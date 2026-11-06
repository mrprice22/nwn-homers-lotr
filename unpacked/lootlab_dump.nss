// lootlab_dump.nss - Loot Lab: for every rolled or socketed item in the admin's
// pack, print its LOOT_* stamps, its engine value against its rarity's budget,
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
        if (Loot_IsRolled(oItem) || nSock > 0)
        {
            string s = Loot_IsRolled(oItem) ? Loot_Describe(oItem)
                     : GetName(oItem) + " [not rolled] sockets "
                       + IntToString(GetLocalInt(oItem, "SOCKET_FILLED")) + "/" + IntToString(nSock);
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
    SendMessageToPC(oPC, "Loot Lab: " + IntToString(nFound) + " rolled or socketed item(s) in your pack.");
}
