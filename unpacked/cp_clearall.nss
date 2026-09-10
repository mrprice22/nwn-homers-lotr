// cp_clearall -- Crash Party: CLEAR ALL. Control-room placeable, OnUsed.
//
// Removes every DM-spawned load object, everywhere, immediately. This is the off
// switch that makes the stress dials safe to turn up.
//
// ## It does not, and must not, touch player inventories
//
// Chaos items handed out at the party belong to the players permanently. There is
// no reclaim button here or anywhere else, by explicit design -- the only thing
// that ever removes a cp_* item is that item spending its last charge in its
// owner's hands. cp_sweep.nss filters on tag equality against CP_LOAD_TAG and
// on creatures/placeables only; keep it that narrow.

#include "cp_dm_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!CP_DmGate(oPC)) return;

    ExecuteScript("cp_sweep", OBJECT_SELF);

    int nKilled = GetLocalInt(GetModule(), "CP_SWEPT");
    SendMessageToPC(oPC, "Cleared " + IntToString(nKilled)
        + " spawned object(s). Player inventories untouched.");
}
