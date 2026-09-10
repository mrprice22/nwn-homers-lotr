// cp_coin -- Crash Party: the Wishing Coin. Wave 2.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
//
// Flip it and take what you get: a 4% chance it simply kills you, and otherwise a
// 10-entry table, half generous, half a joke at your expense. Every table row is
// TEMPORARY and SELF-ONLY, and the downside rows are embarrassing rather than
// dangerous -- no ability drain, nothing that persists after the effect runs out.
// A party item that can leave someone worse off for the rest of the EVENING is a
// party item people stop using; death, in a module that charges nothing for one,
// costs a respawn click and is over. See CP_COIN_DEATH_PCT.
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

// The one outcome that is not temporary and not a joke: the coin kills you.
// Rolled BEFORE the table, so the table's ten rows keep their even odds among
// themselves.
//
// It is affordable here and nowhere else: this module charges NOTHING for a
// death -- no XP, no gold, nothing dropped (respawn_inc.nss says so in its own
// header) -- so the whole cost is a respawn click and the walk back. At a party
// held in the Well of Eru, which is where respawn puts you, that walk is about
// four steps.
//
// A character with outright immunity to death magic shrugs it off and gets the
// message without the funeral. That is the same rare, accepted corner
// fat_inc.nss documents for soul-fatigue, and it is accepted for the same
// reason: the alternative is draining the player to 1 hit point first, which
// leaves an immune character standing in a crowded room one stray hit from a
// real death. A joke item must not do that.
const int CP_COIN_DEATH_PCT = 4;

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

    if (Random(100) < CP_COIN_DEATH_PCT)
    {
        FloatingTextStringOnCreature(GetName(oPC) + " flips a Wishing Coin.", oPC, TRUE);
        SendMessageToPC(oPC, "The coin lands, wobbles, and stops dead on its edge. So do you.");
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_IMPLOSION), GetLocation(oPC));
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectDeath(TRUE, TRUE), oPC);
        CP_Broadcast(GetName(oPC) + " wished for something the coin did not like.",
            COLOR_YELLOW);
        return;
    }

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
