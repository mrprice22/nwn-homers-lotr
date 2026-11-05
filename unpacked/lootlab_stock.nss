// lootlab_stock.nss - Loot Lab: restock the nearest placeable with an inventory
// within 20 m.  A loot container (its OnOpen/OnUsed/OnDeath script is in
// loot/sources.json "scripts") gets exactly what a player would find: one fill
// of ITS profile at ITS loot level (LOOT_LEVEL local, else the area's), old
// contents cleared, refill timer ignored.  Any other container gets 5 rolled
// items at the menu level and floor, as before.
// Roadmap: lo-loot-core, Phase 3 (rng-based-gear-diablo-world-of-warcraft-style). Loot Lab action (emotewand.dlg Entry 19, Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"
#include "loot_chest_inc"

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
    string sProfile = "";
    string sScript = "";
    string sEvt;
    int e;
    for (e = 0; e < 3 && sProfile == ""; e++)
    {
        int nEvt = e == 0 ? EVENT_SCRIPT_PLACEABLE_ON_OPEN
                 : (e == 1 ? EVENT_SCRIPT_PLACEABLE_ON_USED : EVENT_SCRIPT_PLACEABLE_ON_DEATH);
        sEvt = GetStringLowerCase(GetEventScript(oBox, nEvt));
        sProfile = LootD_ScriptProfile(sEvt);
        if (sProfile != "") sScript = sEvt;
    }
    int nMade = 0;
    int i;
    if (sProfile != "")
    {
        object oOld = GetFirstItemInInventory(oBox);
        while (GetIsObjectValid(oOld))
        {
            DestroyObject(oOld);
            oOld = GetNextItemInInventory(oBox);
        }
        int nCLvl = Loot_ContainerLevel(oBox);
        nMade = Loot_FillContainer(oBox, sProfile, nCLvl, oPC);
        SendMessageToPC(oPC, "Loot Lab: filled " + GetName(oBox) + " (" + sScript + ", profile "
                        + sProfile + ") at loot level " + IntToString(nCLvl) + " - area "
                        + GetResRef(GetArea(oBox)) + " is level "
                        + IntToString(Loot_AreaLevel(GetArea(oBox))) + "; " + IntToString(nMade)
                        + " gear roll(s) plus its gold and consumables.");
        return;
    }
    int nLvl = LL_Level(oPC);
    int nFloor = LL_Floor(oPC);
    for (i = 0; i < 5; i++)
        if (GetIsObjectValid(Loot_Roll(nLvl, nFloor, "lab", oPC, oBox)))
            nMade++;
    SendMessageToPC(oPC, "Loot Lab: put " + IntToString(nMade) + " rolled item(s) into "
                    + GetName(oBox) + " (level " + IntToString(nLvl) + "; not a loot container, "
                    + "so the lab level and floor were used).");
}
