// csp_lvl.nss - NWNX_ON_LEVEL_UP_AFTER handler for the caster spell picker.
// Subscribed in onmoduleload.nss, alongside the other subscribers to the same
// event - NWNX_Events runs every one of them.
//
// It replaces the two sk_probe_* subscriptions that were on this event while
// the defect was being diagnosed; those and their scripts are gone.
//
// The picker is opened on a delay: at _AFTER the engine is still finishing the
// level-up with its own UI on screen, and a NUI window opened into that is one
// the player cannot interact with. 4.0s rather than the 2.0s legfeat_lvl uses,
// so that a pure wizard reaching level 60 - who gets both windows in the same
// moment - sees them one after the other rather than stacked.
//
// LEVEL_DOWN is deliberately NOT subscribed. Picks are banked against a
// high-water mark of class level (csp_db.nss), so losing a level takes nothing
// back and regaining it pays nothing again; there is no revoke to run.

#include "csp_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    if (CSP_EnsureAllotment(oPC) <= 0) return;

    DelayCommand(4.0, ExecuteScript("csp_open", oPC));
}
