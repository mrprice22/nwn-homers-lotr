// gem_scan_step.nss - Loot Overhaul Phase 5: one step of the login socket pass.
// OBJECT_SELF = the PC.  Queued by Gem_BeginScan (gem_inc, from gem_login at
// login): reconciles a few queued items per step - giving existing gear the
// sockets loot/sockets.json defines for it, never removing any - then
// reschedules itself.  The per-item work is a table lookup, so the steps only
// exist to keep a full pack of gear well clear of the instruction limit.
#include "gem_inc"

const int GEM_SCAN_PER_STEP = 8;

void main()
{
    object oPC = OBJECT_SELF;
    int nN = GetLocalInt(oPC, "GEM_SCAN_N");
    int i = GetLocalInt(oPC, "GEM_SCAN_I");
    int nEnd = i + GEM_SCAN_PER_STEP;
    for (; i < nN && i < nEnd; i++)
    {
        string sKey = "GEM_SCAN_" + IntToString(i);
        object oItem = GetLocalObject(oPC, sKey);
        DeleteLocalObject(oPC, sKey);
        if (GetIsObjectValid(oItem) && GetItemPossessor(oItem) == oPC)
            Gem_Reconcile(oItem);
    }
    SetLocalInt(oPC, "GEM_SCAN_I", i);
    if (i < nN)
        DelayCommand(0.1, ExecuteScript("gem_scan_step", oPC));
}
