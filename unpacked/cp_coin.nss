// cp_coin -- Crash Party: the Wishing Coin. Wave 2.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
//
// Flip it and take what you get: a 10-entry table, half generous, half a joke at
// your expense. Everything is TEMPORARY and SELF-ONLY, and the downside rows are
// embarrassing rather than dangerous -- no damage that can kill, no ability
// drain, nothing that persists after the effect runs out. A party item that can
// leave someone worse off for the rest of the evening is a party item people stop
// using.
//
// ## Why the coin grants no attack or damage bonus at all
//
// It cannot do it safely, and "safely" has two independent walls.
//
// Applying EffectAttackIncrease raw is out: same-type bonuses do not stack in
// NWN -- the engine keeps the HIGHEST and discards the rest -- so a raw +2 here
// would silently SUPPRESS the player's Bard Song and legendary feats for its
// whole duration (CLAUDE-gotchas.md).
//
// The sanctioned alternative, registering it with the bonus ledger
// (bonus_pool_inc.nss), is worse HERE for a reason specific to this item: ledger
// entries are LocalInts on the creature, which serialise into the .bic, while
// their expiry is a DelayCommand, which dies at logout. BPool_ClearTransient
// only sweeps sources listed in the ledger's own source table, and an ad-hoc
// "cp_coin" source is not in it -- so flip the coin, log out inside the minute,
// and you come back holding a PERMANENT +2 attack. On a 240-charge party toy
// handed to everyone at the door, that is a character-buff exploit, not a bug.
//
// So every row below is a temporary EFFECT and nothing else. Effects are dropped
// at logout by the engine, which makes the whole class of problem go away.

#include "cp_inc"

const float CP_COIN_DUR = 60.0;

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (CP_Spam(oPC, "cp_coin_cd", 5.0)) return;

    object oItem = CP_FindItem(oPC, "cp_coin");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(4),
            "The coin lands on its edge, splits neatly in two and is gone."))
        return;

    AssignCommand(oPC, ActionPlayAnimation(ANIMATION_FIREFORGET_TAUNT, 1.0));

    string sMsg;
    effect e;
    int nRoll = Random(10);

    switch (nRoll)
    {
        case 0:
            sMsg = "The coin blazes gold. You feel unstoppable!";
            e = EffectHaste();
            break;
        case 1:
            sMsg = "The coin hums. Your skin turns to stone-hard lacquer.";
            e = EffectACIncrease(6, AC_DODGE_BONUS);
            break;
        case 2:
            sMsg = "The coin flares. You are wreathed in harmless glory.";
            e = EffectVisualEffect(VFX_DUR_AURA_PULSE_YELLOW_WHITE);
            break;
        case 3:
            sMsg = "The coin sings. You feel enormous.";
            e = EffectTemporaryHitpoints(50);
            break;
        case 4:
            sMsg = "The coin whispers something encouraging.";
            e = EffectSavingThrowIncrease(SAVING_THROW_ALL, 5);
            break;
        case 5:
            sMsg = "The coin sulks. You feel weirdly clumsy.";
            e = EffectAbilityDecrease(ABILITY_DEXTERITY, 4);
            break;
        case 6:
            sMsg = "The coin sniggers. Everything looks very far away.";
            e = EffectVisualEffect(VFX_DUR_BLUR);
            break;
        case 7:
            sMsg = "The coin buzzes. You cannot stop twitching.";
            e = EffectVisualEffect(VFX_DUR_GLOW_LIGHT_YELLOW);
            AssignCommand(oPC, ActionPlayAnimation(ANIMATION_LOOPING_SPASM, 1.0, 6.0));
            break;
        case 8:
            sMsg = "The coin goes cold. You smell faintly of wet dog.";
            e = EffectVisualEffect(VFX_DUR_GLOW_BROWN);
            break;
        default:
            sMsg = "The coin does absolutely nothing. Somehow that is worse.";
            e = EffectVisualEffect(VFX_IMP_HEAD_ODD);
            break;
    }

    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, e, oPC, CP_COIN_DUR);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_MAGBLUE), oPC);
    SendMessageToPC(oPC, sMsg);
    FloatingTextStringOnCreature(GetName(oPC) + " flips a Wishing Coin.", oPC, TRUE);
}
