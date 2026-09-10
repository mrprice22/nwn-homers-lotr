// cp_eru_enter -- Crash Party: Well of Eru OnEnter wrapper.
//
// Chains the area's previous OnEnter (prsg_enter, which itself chains
// welloferuenter) unchanged, then does the party's two per-arrival jobs. Same
// wrapper pattern as prsg_enter / q_maz_ent1 / q_brn_ent1.
//
//   1. The commemorative souvenir, once per character, ever.
//   2. The wave catch-up grant -- everything released so far that this character
//      has not already had. This is what makes a late arrival whole: walk in
//      during wave 3 and you leave with waves 0-3.
//
// Both are no-ops when CP_MODE is off, so outside the event this costs one
// LocalInt read on the module.

#include "cp_inc"

void main()
{
    // The area's whole previous OnEnter behaviour, unchanged.
    ExecuteScript("prsg_enter", OBJECT_SELF);

    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (!CP_IsOn()) return;

    // Souvenir: no properties, no charges, no expiry, and no sweep touches it.
    if (!CP_HasGrant(oPC, "cp_souvenir"))
    {
        // One at a time -- CreateItemOnObject's stack argument is clamped to the
        // base item's Stacking value (CLAUDE-gotchas.md), so a count would lie.
        object oSouv = CreateItemOnObject("cp_souvenir", oPC);
        if (GetIsObjectValid(oSouv))
        {
            SetIdentified(oSouv, TRUE);
            CP_MarkGrant(oPC, "cp_souvenir");
            SendMessageToPC(oPC,
                "You are handed a commemorative tankard. Yours to keep, whatever happens tonight.");
        }
    }

    CP_GrantUpToWave(oPC);
}
