// cp_eru_enter -- Crash Party: Well of Eru OnEnter wrapper.
//
// Chains the area's previous OnEnter (prsg_enter, which itself chains
// welloferuenter) unchanged, then does the party's two per-arrival jobs. Same
// wrapper pattern as prsg_enter / q_maz_ent1 / q_brn_ent1.
//
//   1. The wave catch-up grant, for players who have already opted in --
//      everything released so far that this character has not had. This is what
//      makes a late arrival whole: walk in during wave 3 and you leave with
//      waves 0-3 together.
//   2. The commemorative souvenir, once per character.
//   3. A nudge toward the penguin for anyone who has not opted in.
//
// ## Why nothing is handed out unprompted any more
//
// The party is opt-in, ONE CHARACTER PER ACCOUNT, and Bartholomew the penguin
// holds that conversation. Handing gear to whoever walked through the door would
// let an account claim a set on every alt it cared to roll -- the items are
// undroppable so they could not be pooled, but the souvenir is meant to mean
// something. CP_GrantUpToWave enforces it; this script just calls it, so a
// non-crasher silently gets nothing and is pointed at the penguin instead.
//
// All of it is a no-op when CP_MODE is off, so outside the event this costs one
// LocalInt read on the module.

#include "cp_inc"

void main()
{
    // The area's whole previous OnEnter behaviour, unchanged.
    ExecuteScript("prsg_enter", OBJECT_SELF);

    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (!CP_IsOn()) return;

    // Not signed up: one nudge, then leave them alone. Throttled so it is not
    // repeated every time somebody crosses the area boundary.
    if (!CP_IsCrasher(oPC))
    {
        if (!CP_Spam(oPC, "cp_nudge", 600.0))
            SendMessageToPC(oPC,
                "Bartholomew the Party Penguin is handing out party favours by the "
                + "Well. One character per account can sign up.");
        return;
    }

    // Souvenir: no properties, no charges, no expiry. Reclaimed only if this
    // character opts out, which also clears the grant so it can be re-issued.
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
