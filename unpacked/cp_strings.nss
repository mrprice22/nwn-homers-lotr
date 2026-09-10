// cp_strings -- Crash Party: Puppet Strings of Bard's Folly. Wave 1.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC, and
// the chosen target is stashed by the dispatcher (CP_Target).
//
// Point it at somebody and they dance. It is a DANCE-LOCK, NOT A STUN: a short
// ActionPlayAnimation the target can walk out of, with no effect applied, so it
// cannot be used to interrupt a fight or grief anyone. That restraint is the
// whole design -- an item that could actually disable a player would not survive
// contact with a crowded party.

#include "cp_inc"

int CP_SillyAnim()
{
    switch (Random(6))
    {
        case 0: return ANIMATION_LOOPING_SPASM;
        case 1: return ANIMATION_LOOPING_GET_LOW;
        case 2: return ANIMATION_LOOPING_TALK_LAUGHING;
        case 3: return ANIMATION_LOOPING_MEDITATE;
        case 4: return ANIMATION_LOOPING_WORSHIP;
    }
    return ANIMATION_LOOPING_TALK_FORCEFUL;
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (CP_Spam(oPC, "cp_str_cd", 3.0)) return;

    object oItem = CP_FindItem(oPC, "cp_strings");
    if (!GetIsObjectValid(oItem)) return;

    // PLAYERS ONLY, and this is a security boundary rather than flavour.
    //
    // The effect is ClearAllActions + a 6-10s ActionPlayAnimation. On another
    // PLAYER that is a joke they can walk straight out of. On an NPC it is a
    // functional STUN: clearing a hostile creature's action queue mid-fight
    // interrupts whatever it was casting or swinging, and at 400 charges that is
    // a pocket crowd-control item that trivialises every boss in the module.
    // Restricting the target to PCs removes the exploit completely instead of
    // trying to tune around it.
    object oTarget = CP_Target(oPC);
    if (!GetIsObjectValid(oTarget) || !GetIsPC(oTarget) || GetIsDM(oTarget))
    {
        SendMessageToPC(oPC, "The strings only answer for another player.");
        return;   // no charge spent on a fumbled aim
    }

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(2),
            "The strings snap and coil away into nothing."))
        return;

    float fDur = IntToFloat(Random(5) + 6);   // 6-10s

    AssignCommand(oTarget, ClearAllActions(TRUE));
    AssignCommand(oTarget, ActionPlayAnimation(CP_SillyAnim(), 1.0, fDur));
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_HEAD_SONIC), oTarget);
    AssignCommand(oPC, PlaySound("as_pl_tavsongm2"));

    FloatingTextStringOnCreature(
        GetName(oTarget) + " is seized by an irresistible urge to perform!",
        oTarget, TRUE);
    if (oTarget != oPC)
        SendMessageToPC(oTarget, GetName(oPC) + " is pulling your strings.");
}
