// forge_scan_step - one step of a chunked contraband scan.
//
// Run via ExecuteScript on the PC (OBJECT_SELF = the player) from
// ForgeBeginScan / ForgeBeginWardenScan (forge_inc). Evaluates the single queued
// item at the cursor, then reschedules itself for the next item. Processing one
// item per delayed action keeps every step well under the NWScript instruction
// cap, so a full inventory of high-end gear can no longer blow up either the
// login enter scripts or the Forge Warden's dialog gates.
//
// Two modes (FORGE_SCAN_MODE):
//   0 = LOGIN  - an illegal item jails the bearer and stops the scan.
//   1 = WARDEN - an illegal item records the contraband verdict
//                (FORGE_WARDEN_DIRTY=1, FORGE_ILLEGAL_ITEM) without jailing and
//                stops; draining the queue clean sets FORGE_WARDEN_DIRTY=0.
//                Either way FORGE_WARDEN_READY=1 marks the verdict as known, so
//                forge_ward_c_il / forge_ward_c_ok read it in O(1).
//
// Items confirmed legal are stamped FORGE_CLEAN = FORGE_CLEAN_VER (both modes)
// so later scans skip them. INDETERMINATE items (valuation infrastructure
// unavailable) are left unstamped to be re-checked next time.

#include "forge_inc"

void main()
{
    object oPC = OBJECT_SELF;
    int nMode = GetLocalInt(oPC, "FORGE_SCAN_MODE");

    int nN = GetLocalInt(oPC, "FORGE_SCAN_N");
    int i  = GetLocalInt(oPC, "FORGE_SCAN_I");
    if (i >= nN)
        return; // queue drained (or scan superseded)

    string sKey = "FORGE_SCAN_" + IntToString(i);
    object oItem = GetLocalObject(oPC, sKey);
    DeleteLocalObject(oPC, sKey);
    SetLocalInt(oPC, "FORGE_SCAN_I", i + 1);

    if (GetIsObjectValid(oItem)
        && GetLocalInt(oItem, "FORGE_CLEAN") != FORGE_CLEAN_VER)
    {
        int nVerdict = ForgeItemLegality(oItem);
        if (nVerdict == FORGE_LEG_ILLEGAL)
        {
            if (nMode == 1)
            {
                SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oItem);
                SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", TRUE);
                SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
            }
            else
                ForgeJailForItem(oPC, oItem);
            return; // stop scanning - verdict is dirty
        }
        if (nVerdict == FORGE_LEG_LEGAL)
            SetLocalInt(oItem, "FORGE_CLEAN", FORGE_CLEAN_VER);
        // INDETERMINATE: leave unstamped, re-evaluate next scan.
    }

    if (i + 1 < nN)
    {
        DelayCommand(0.1, ExecuteScript("forge_scan_step", oPC));
        return;
    }

    // Queue drained with no illegal item found.
    if (nMode == 1)
    {
        SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", FALSE);
        DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
        SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
    }
}
