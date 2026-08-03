// devcrit_eff.nss - NWNX_ON_EFFECT_APPLIED_BEFORE handler.
//
// Roadmap: devcrit-roll. SAFETY NET ONLY - read this before trusting it.
//
// It was written as the half of the rework that stops the kill, on the theory
// that the engine delivers a Devastating Critical kill as an EffectDeath. UAT
// disproved that: a devastating critical killed a target that was BOTH flagged
// here and carrying EffectImmunity(IMMUNITY_TYPE_DEATH). The real fix is
// upstream - the blank EpicWeaponDevastatingCriticalFeat column in
// hak_2da/baseitems.2da means the engine never rolls the save at all (see
// bin/gen-devcrit-map.py and the header of devcrit_atk.nss).
//
// This is kept for the one case that can still resolve an engine devastating
// critical: a server or client running a hak from before that change. It
// refuses that death effect if it can, and lets every other death in the
// module through untouched.
//
// Registered from onmoduleload.nss:
//     NWNX_Events_SubscribeEvent(NWNX_ON_EFFECT_APPLIED_BEFORE, "devcrit_eff");
//
// OBJECT_SELF is the TARGET of the effect. The module already subscribes the
// _AFTER half of this same event for eff_dur_x2.nss - that file is the pattern
// for reading event data here.
//
// This fires for every temporary and permanent effect applied on the server, so
// the type test is first and everything else leaves immediately.

#include "devcrit_inc"

void main()
{
    // "TYPE" is the internal NWNXLib effect enum, NOT an NWScript EFFECT_TYPE_*
    // constant - see DEVCRIT_EFFTYPE_DEATH in devcrit_inc.nss.
    int nType = StringToInt(NWNX_Events_GetEventData("TYPE"));

    object oTarget = OBJECT_SELF;

    if (nType != DEVCRIT_EFFTYPE_DEATH)
    {
        // Diagnostic mode only, and only for a victim already inside a
        // devastating critical's window: dump what the engine IS applying, so
        // a wrong DEVCRIT_EFFTYPE_DEATH (the kill arriving under a different
        // enum) can be told apart from the kill not being an applied effect at
        // all. The module check comes first so the normal hot path - every
        // effect applied on the server - is one GetLocalInt as before.
        if (DevCrit_IsDebug() && DevCrit_IsNoKill(oTarget))
            DevCrit_Debug(oTarget, "effect applied inside window, TYPE=" +
                          IntToString(nType));
        return;
    }

    // A death effect from anything else - Finger of Death, a rogue's Death
    // Attack, Weird, a DM, a plot script - is none of our business. Only a
    // death arriving inside the window devcrit_atk.nss opened is refused.
    if (!DevCrit_IsNoKill(oTarget)) return;

    if (DevCrit_IsDebug())
        DevCrit_Debug(oTarget, "death effect inside window - REFUSED");

    NWNX_Events_SkipEvent();
}
