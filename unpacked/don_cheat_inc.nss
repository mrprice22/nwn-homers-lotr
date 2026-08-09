#include "don_cheat_data"

// don_cheat_inc.nss
// Donations Chest "cheat stock" - keeps exactly one copy of every best-in-slot
// item from don_cheat_data.nss sitting in the Well of Eru Donations Chest.
//
// The chest is topped back up every time it is closed, so a player who takes an
// item finds a fresh copy waiting on the next open - but never more than one
// copy of any listed item at a time.
//
// ---------------------------------------------------------------------------
//  MASTER SWITCH - flip this to FALSE and repack to turn the cheat chest off.
// ---------------------------------------------------------------------------
//  TRUE  = the chest restocks itself with the best-in-slot table (test/dev).
//  FALSE = nothing is ever created; the normal per-reset donations loot in
//          welloferuenter.nss carries on as usual. Items already handed out
//          are NOT reclaimed - this is an "off from now on" switch.
//
//  This is the one line to change before a season goes live.
// ---------------------------------------------------------------------------
const int DON_CHEAT_ENABLED = TRUE;

// Tops the chest back up: creates any listed item that is not already inside it.
// Safe to call repeatedly - one pass marks what is present, the second pass only
// fills the gaps, so the chest can never accumulate a second copy of an item.
void DonCheatRestock(object oChest)
{
    if (!DON_CHEAT_ENABLED) return;
    if (!GetIsObjectValid(oChest)) return;

    // Presence is stamped with a per-run serial, so no cleanup pass is needed:
    // a stale stamp from an earlier run simply fails the == nRun test.
    int nRun = GetLocalInt(oChest, "DON_CHEAT_RUN") + 1;
    SetLocalInt(oChest, "DON_CHEAT_RUN", nRun);

    object oItem = GetFirstItemInInventory(oChest);
    while (GetIsObjectValid(oItem))
    {
        SetLocalInt(oChest, "DCT_" + GetResRef(oItem), nRun);
        oItem = GetNextItemInInventory(oChest);
    }

    int i;
    for (i = 0; i < DON_CHEAT_COUNT; i++)
    {
        string sRes = DonCheatResRef(i);
        if (sRes == "") continue;
        if (GetLocalInt(oChest, "DCT_" + sRes) == nRun) continue;

        // Stamp before creating so a duplicated table row can't double-stock.
        SetLocalInt(oChest, "DCT_" + sRes, nRun);
        object oNew = CreateItemOnObject(sRes, oChest, DonCheatStack(i));
        SetIdentified(oNew, TRUE);
    }
}
