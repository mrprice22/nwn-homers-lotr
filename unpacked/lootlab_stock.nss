// lootlab_stock.nss - Loot Lab: put 5 rolled items (menu level and floor) into the
// nearest placeable with an inventory within 20 m - a stand-in for the Phase 3
// chest refill, to see rolled loot come out of a container the way players will.
// Roadmap: lo-loot-core. Loot Lab action (emotewand.dlg Entry 19, Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    object oBox = OBJECT_INVALID;
    int n = 1;
    object o = GetNearestObject(OBJECT_TYPE_PLACEABLE, oPC, n);
    while (GetIsObjectValid(o) && GetDistanceBetween(oPC, o) <= 20.0)
    {
        if (GetHasInventory(o)) { oBox = o; break; }
        o = GetNearestObject(OBJECT_TYPE_PLACEABLE, oPC, ++n);
    }
    if (!GetIsObjectValid(oBox))
    {
        SendMessageToPC(oPC, "Loot Lab: no container within 20 m.");
        return;
    }
    int nLvl = LL_Level(oPC);
    int nFloor = LL_Floor(oPC);
    int nMade = 0;
    int i;
    for (i = 0; i < 5; i++)
        if (GetIsObjectValid(Loot_Roll(nLvl, nFloor, "lab", oPC, oBox)))
            nMade++;
    SendMessageToPC(oPC, "Loot Lab: put " + IntToString(nMade) + " rolled item(s) into "
                    + GetName(oBox) + " (level " + IntToString(nLvl) + ").");
}
