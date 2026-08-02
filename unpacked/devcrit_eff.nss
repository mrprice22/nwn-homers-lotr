// devcrit_eff.nss — NWNX_ON_EFFECT_APPLIED_BEFORE handler.
//
// Roadmap: devcrit-roll. The engine delivers the Devastating Critical kill as
// an EffectDeath, not as damage, so the damage event cannot stop it. This
// handler is the second half of the rework: it refuses that one death effect
// and lets every other death in the module through untouched.
//
// Registered from onmoduleload.nss:
//     NWNX_Events_SubscribeEvent(NWNX_ON_EFFECT_APPLIED_BEFORE, "devcrit_eff");
//
// OBJECT_SELF is the TARGET of the effect. The module already subscribes the
// _AFTER half of this same event for eff_dur_x2.nss — that file is the pattern
// for reading event data here.
//
// This fires for every temporary and permanent effect applied on the server, so
// the type test is first and everything else leaves immediately.

#include "devcrit_inc"

void main()
{
    // "TYPE" is the internal NWNXLib effect enum, NOT an NWScript EFFECT_TYPE_*
    // constant — see DEVCRIT_EFFTYPE_DEATH in devcrit_inc.nss.
    if (StringToInt(NWNX_Events_GetEventData("TYPE")) != DEVCRIT_EFFTYPE_DEATH)
        return;

    object oTarget = OBJECT_SELF;

    // A death effect from anything else — Finger of Death, a rogue's Death
    // Attack, Weird, a DM, a plot script — is none of our business. Only a
    // death arriving inside the window devcrit_atk.nss opened is refused.
    if (!DevCrit_IsNoKill(oTarget)) return;

    NWNX_Events_SkipEvent();
}
