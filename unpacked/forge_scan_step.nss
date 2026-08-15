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
//   2 = REVERT  - the Warden's "revert all to stock" action. Every illegal item
//                is reverted to its stock blueprint; this mode does NOT stop on
//                the first one, it drains the whole queue. Items with no known
//                blueprint tally into FORGE_RVT_FAIL and stay illegal. On drain,
//                a zero tally releases the player from the Pit Prison; a
//                non-zero one leaves the dirty verdict standing so the dialog's
//                "remains unlawful" branch (forge_ward_c_il) shows.
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
            if (nMode == 2)
            {
                // Revert-all: fix it and keep going. A missing blueprint is the
                // only failure - tally it and leave the item alone.
                if (!GetIsObjectValid(ForgeRevertToBlueprint(oItem, oPC)))
                {
                    SetLocalInt(oPC, "FORGE_RVT_FAIL",
                        GetLocalInt(oPC, "FORGE_RVT_FAIL") + 1);
                    SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oItem);
                }
            }
            else if (nMode == 1)
            {
                SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oItem);
                SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", TRUE);
                SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
                return; // stop scanning - verdict is dirty
            }
            else
            {
                ForgeJailForItem(oPC, oItem);
                return; // stop scanning - verdict is dirty
            }
        }
        else if (nVerdict == FORGE_LEG_LEGAL)
            SetLocalInt(oItem, "FORGE_CLEAN", FORGE_CLEAN_VER);
        // INDETERMINATE: leave unstamped, re-evaluate next scan.
    }

    if (i + 1 < nN)
    {
        DelayCommand(0.1, ExecuteScript("forge_scan_step", oPC));
        return;
    }

    // Queue drained.
    if (nMode == 2)
    {
        int nFail = GetLocalInt(oPC, "FORGE_RVT_FAIL");
        ForgeLog("forge_scan_step: revert-all drained for " + GetName(oPC)
            + ", " + IntToString(nFail) + " item(s) had no blueprint");
        SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", nFail > 0);
        SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
        if (nFail > 0)
            return; // items remain unlawful - the warden keeps them here
        DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
        ForgeReleaseFromJail(oPC);
        return;
    }
    if (nMode == 1)
    {
        SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", FALSE);
        DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
        SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
    }
}
