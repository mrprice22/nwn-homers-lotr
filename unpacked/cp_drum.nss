// cp_drum -- Crash Party: Drum of the Marching Band. Wave 1.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
//
// Bangs the drum and everyone nearby falls into step whether they meant to or
// not: one synced animation and one sound, across every player in a 10m sphere.
//
// ## Players only, and that is a security boundary
//
// Forcing an animation means ClearAllActions on the target. On another PLAYER
// that is a joke they walk straight out of. On a hostile NPC it is a functional
// STUN -- it interrupts whatever the creature was casting or swinging -- and an
// area-effect version of that would be far worse than the single-target Puppet
// Strings, which was restricted for exactly this reason. So the sphere is walked
// for PCs and nothing else.
//
// ## Why this is the cheapest "stress" item in the set
//
// It creates no objects at all. The load it makes is pure broadcast: N clients
// each told to play an animation and a sound in the same frame. That is a
// genuinely different shape from the object-count pressure the DM dials make,
// and it is the shape a real crowd produces.

#include "cp_inc"

const float CP_DRUM_RADIUS = 10.0;

int CP_MarchAnim(int nBeat)
{
    switch (nBeat)
    {
        case 0: return ANIMATION_LOOPING_GET_LOW;
        case 1: return ANIMATION_FIREFORGET_SALUTE;
        case 2: return ANIMATION_FIREFORGET_BOW;
        case 3: return ANIMATION_LOOPING_WORSHIP;
    }
    return ANIMATION_FIREFORGET_VICTORY2;
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (CP_Spam(oPC, "cp_drum_cd", 8.0)) return;

    object oItem = CP_FindItem(oPC, "cp_drum");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(6),
            "The drumskin splits with a final flat thud and the hoop clatters apart."))
        return;

    // One roll for the whole band, so everybody does the SAME thing -- a
    // different animation each would just look like noise.
    int nBeat = Random(5);
    int nAnim = CP_MarchAnim(nBeat);
    float fDur = 4.0;

    AssignCommand(oPC, PlaySound("as_pl_tavsongm2"));
    FloatingTextStringOnCreature(
        GetName(oPC) + " strikes up a marching beat!", oPC, TRUE);

    int nCaught = 0;
    object oTarget = GetFirstObjectInShape(SHAPE_SPHERE, CP_DRUM_RADIUS,
                                           GetLocation(oPC), FALSE,
                                           OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(oTarget))
    {
        if (GetIsPC(oTarget) && !GetIsDM(oTarget))
        {
            AssignCommand(oTarget, ClearAllActions(TRUE));
            AssignCommand(oTarget, ActionPlayAnimation(nAnim, 1.0, fDur));
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectVisualEffect(VFX_IMP_HEAD_SONIC), oTarget);
            if (oTarget != oPC)
                SendMessageToPC(oTarget, "You find yourself marching in step.");
            nCaught++;
        }
        oTarget = GetNextObjectInShape(SHAPE_SPHERE, CP_DRUM_RADIUS,
                                       GetLocation(oPC), FALSE,
                                       OBJECT_TYPE_CREATURE);
    }

    SendMessageToPC(oPC, "The band falls in: " + IntToString(nCaught) + " marching.");
}
