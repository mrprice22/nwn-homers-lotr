//::///////////////////////////////////////////////
//:: Divine Power
//:: NW_S0_DivPower.nss
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    Improves the Clerics attack to be the
    equivalent of a Fighter's BAB of the same level,
    +1 HP per level and raises their strength to
    18 if is not already there.
*/
//:://////////////////////////////////////////////
//:: Created By: Preston Watamaniuk
//:: Created On: Oct 21, 2001
//:://////////////////////////////////////////////

/*
bugfix by Kovi 2002.07.22
- temporary hp was stacked
- loosing temporary hp resulted in loosing the other bonuses
- number of attacks was not increased (should have been a BAB increase)
still problem:
~ attacks are better still approximation (the additional attack is at full BAB)
~ attack/ability bonuses count against the limits
*/

//:: MODULE FORK, 2026-08-06 (roadmap: spell-ab-prowess-stack).
//:: Divine Power's attack bonus is registered with the per-creature bonus
//:: ledger instead of being linked as an effect, so it is felt alongside
//:: Legendary Prowess rather than hidden behind it. NOTE this bonus is computed
//:: as "raise BAB to character level" and is therefore ZERO for most level-60
//:: characters already - pooling it changes nothing for them; it is the low-BAB
//:: caster who was losing the whole spell.
//:: The extra attacks (EffectModifyAttacks) and the strength bonus stay in the
//:: link, which is also what the ledger witnesses.
#include "nw_i0_spells"


#include "x2_inc_spellhook"
#include "bonus_pool_inc"

void main()
{

/*
  Spellcast Hook Code
  Added 2003-06-23 by GeorgZ
  If you want to make changes to all spells,
  check x2_inc_spellhook.nss to find out more

*/

    if (!X2PreSpellCastCode())
    {
        // If code within the PreSpellCastHook (i.e. UMD) reports FALSE, do not run this spell
        return;
    }

// End of Spell Cast Hook

    //Declare major variables
    object oTarget = GetSpellTargetObject();

    RemoveEffectsFromSpell(oTarget, GetSpellId());
    RemoveTempHitPoints();

    int nCasterLevel = GetCasterLevel(OBJECT_SELF);
    int nTotalCharacterLevel = GetHitDice(OBJECT_SELF);
    int nBAB = GetBaseAttackBonus(OBJECT_SELF);
    int nEpicPortionOfBAB = ( nTotalCharacterLevel - 19 ) / 2;

    if ( nEpicPortionOfBAB < 0 )
    {
        nEpicPortionOfBAB = 0;
    }

    int nExtraAttacks = 0;
    int nAttackIncrease = 0;

    if ( nTotalCharacterLevel > 20 )
    {
        nAttackIncrease = 20 + nEpicPortionOfBAB;
        if( nBAB - nEpicPortionOfBAB < 11 )
        {
            nExtraAttacks = 2;
        }
        else if( nBAB - nEpicPortionOfBAB > 10 && nBAB - nEpicPortionOfBAB < 16)
        {
            nExtraAttacks = 1;
        }
    }
    else
    {
        nAttackIncrease = nTotalCharacterLevel;
        nExtraAttacks = ( ( nTotalCharacterLevel - 1 ) / 5 ) - ( ( nBAB - 1 ) / 5 );
    }
    nAttackIncrease -= nBAB;

    if ( nAttackIncrease < 0 )
    {
        nAttackIncrease = 0;
    }

    int nStr = GetAbilityScore(oTarget, ABILITY_STRENGTH);
    int nStrengthIncrease = (nStr - 18) * -1;
    if( nStrengthIncrease < 0 )
    {
        nStrengthIncrease = 0;
    }

    effect eVis = EffectVisualEffect(VFX_IMP_SUPER_HEROISM);
    effect eStrength = EffectAbilityIncrease(ABILITY_STRENGTH, nStrengthIncrease);
    effect eHP = EffectTemporaryHitpoints(nCasterLevel);
    // nAttackIncrease is pooled, not linked - see the header note.
    effect eAttackMod = EffectModifyAttacks(nExtraAttacks);
    effect eDur = EffectVisualEffect(VFX_DUR_CESSATE_POSITIVE);
    effect eLink = EffectLinkEffects(eAttackMod, eDur);

    //Make sure that the strength modifier is a bonus
    if( nStrengthIncrease > 0 )
    {
        eLink = EffectLinkEffects(eLink, eStrength);
    }

    //Meta-Magic
    int nMetaMagic = GetMetaMagicFeat();
    if( nMetaMagic == METAMAGIC_EXTEND )
    {
        nCasterLevel *= 2;
    }

    //Fire cast spell at event for the specified target
    SignalEvent(oTarget, EventSpellCastAt(OBJECT_SELF, SPELL_DIVINE_POWER, FALSE));

    //Apply Link and VFX effects to the target
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLink, oTarget, RoundsToSeconds(nCasterLevel));
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eHP, oTarget, RoundsToSeconds(nCasterLevel));
    BPool_SpellAttack(oTarget, BPOOL_SRC_DIVPOW, nAttackIncrease, RoundsToSeconds(nCasterLevel));
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oTarget);
}

