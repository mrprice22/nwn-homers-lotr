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
    CBD_Immune(oSelf, IMMUNITY_TYPE_DEATH);

    // ...and neither is being KILLED WITHOUT A DEATH EFFECT, which is how
    // players were destroying the dummy mid-trial (roadmap
    // combat-dummy-can-be-slain). Two engine paths, neither of them damage and
    // neither of them an EffectDeath the immunity above could see:
    //
    //   * HELPLESS -> COUP DE GRACE. Flame of the West carries On Hit: Hold at
    //     DC 20 (the Epic variant Stun), and the dummy's Will save is +2 - it
    //     fails almost every time, and eff_dur_x2 then doubles the duration. A
    //     confirmed critical on a helpless target is an engine combat OUTCOME:
    //     it kills outright, ahead of the heal-back and around the death
    //     immunity. Paralysis/stun/sleep/daze/knockdown immunity is what stops
    //     it, because it stops the dummy ever being helpless in the first place.
    //   * DRAIN TO ZERO. The Katana of Dol Guldur carries On Hit: Level Drain at
    //     DC 14, and this is a ONE-level creature: a single failed Fortitude
    //     save takes it to level 0, which the engine treats as death whatever
    //     its 10000 hit points say. (A player confirmed the path from the other
    //     side by casting Negative Energy Protection on the dummy.) Ability
    //     drain to 0 Constitution is the same shape.
    //
    // The mind-affecting set is not lethal, but a dominated, confused or fleeing
    // dummy is a ruined trial just the same, and it is free to close here.
    CBD_Immune(oSelf, IMMUNITY_TYPE_PARALYSIS);
    CBD_Immune(oSelf, IMMUNITY_TYPE_STUN);
    CBD_Immune(oSelf, IMMUNITY_TYPE_SLEEP);
    CBD_Immune(oSelf, IMMUNITY_TYPE_DAZED);
    CBD_Immune(oSelf, IMMUNITY_TYPE_KNOCKDOWN);
    CBD_Immune(oSelf, IMMUNITY_TYPE_NEGATIVE_LEVEL);
    CBD_Immune(oSelf, IMMUNITY_TYPE_ABILITY_DECREASE);
    CBD_Immune(oSelf, IMMUNITY_TYPE_MIND_SPELLS);
    CBD_Immune(oSelf, IMMUNITY_TYPE_CHARM);
    CBD_Immune(oSelf, IMMUNITY_TYPE_DOMINATE);
    CBD_Immune(oSelf, IMMUNITY_TYPE_CONFUSED);
    CBD_Immune(oSelf, IMMUNITY_TYPE_FEAR);

    // What must NEVER be added here: IMMUNITY_TYPE_CRITICAL_HIT,
    // IMMUNITY_TYPE_SNEAK_ATTACK, EffectDamageImmunity, EffectDamageReduction -
    // and the Plot flag and SetImmortal, for the same reason. Every one of them
    // changes the number the dummy exists to measure, which is exactly how the
    // first UAT of the feature ended up reporting a DPR of 0. Indestructibility
    // is only ever bought here from things that are NOT damage.

    Cbd_InitDb();
}
