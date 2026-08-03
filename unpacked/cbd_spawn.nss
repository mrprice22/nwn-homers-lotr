// cbd_spawn.nss - Combat Dummy OnSpawn.
//
// The dummy is placed by hand from the toolset into any area, so everything it
// needs is set up here rather than by a spawner: no waypoint, no area script,
// no per-area wiring.
//
// Deliberately does NOT call the default AI spawn script - the dummy has no
// combat AI at all. It stands still, hostile, and is hit.

#include "nwnx_damage"
#include "cbd_inc"

void main()
{
    object oSelf = OBJECT_SELF;

    SetLocalInt(oSelf, CBD_VAR_IS_DUMMY, 1);
    SetLocalLocation(oSelf, CBD_VAR_SPAWN, GetLocation(oSelf));
    DeleteLocalInt(oSelf, CBD_VAR_COOL);
    CBD_ClearState(oSelf);

    // The damage handler is what measures DPR and what heals the dummy back to
    // full after every hit (the damage itself lands, so the combat log shows
    // it). Per-object: this registration applies to this dummy only.
    NWNX_Damage_SetDamageEventScript("cbd_damage", oSelf);

    // Rooted to the spot: it must never chase, and it must never wander out of
    // the spot the builder placed it on.
    effect eHold = SupernaturalEffect(EffectCutsceneImmobilize());
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eHold, oSelf);

    // Damage is healed straight back off by cbd_damage, but death EFFECTS are
    // not damage - Finger of Death and friends would still drop it.
    effect eNoDeath = SupernaturalEffect(EffectImmunity(IMMUNITY_TYPE_DEATH));
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eNoDeath, oSelf);

    Cbd_InitDb();
}
