//::///////////////////////////////////////////////
//:: War Cry
//:: NW_S0_WarCry
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    The bard lets out a terrible shout that gives
    him a +2 bonus to attack and damage and causes
    fear in all enemies that hear the cry
*/
//:://////////////////////////////////////////////
//:: Created By: Preston Watamaniuk
//:: Created On: Oct 22, 2001
//:://////////////////////////////////////////////

//:: MODULE FORK, 2026-08-06 (roadmap: spell-ab-prowess-stack).
//:: This is the spell Szescian82 reported: the +2 attack bonus moved a
//:: Legendary Prowess holder's to-hit by NOTHING, because same-type
//:: attack-bonus effects do not stack and the feat's permanent +5 was always
//:: the larger. The attack half is now registered with the per-creature bonus
//:: ledger. The +2 DAMAGE stays a linked effect (different damage types already
//:: stack), and so does the fear half, so the caster's link still carries the
//:: duration VFX that the ledger uses as its witness.
#include "X2_I0_SPELLS"
#include "x2_inc_spellhook"
#include "bonus_pool_inc"

void main()
{

/*
  Spellcast Hook Code
  Added 2003-06-20 by Georg
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
    object oTarget;
    int nLevel = GetCasterLevel(OBJECT_SELF);
    int nAttack = 2;   // pooled, not linked - see the header note
    effect eDamage = EffectDamageIncrease(2, DAMAGE_TYPE_SLASHING);
    effect eFear = EffectFrightened();
    effect eVis = EffectVisualEffect(VFX_IMP_HEAD_SONIC);
    effect eVisFear = EffectVisualEffect(VFX_DUR_MIND_AFFECTING_FEAR);
    effect eLOS;
    if(GetGender(OBJECT_SELF) == GENDER_FEMALE)
    {
        eLOS = EffectVisualEffect(290);
    }
    else
    {
        eLOS = EffectVisualEffect(VFX_FNF_HOWL_WAR_CRY);
    }

    effect eDur = EffectVisualEffect(VFX_DUR_CESSATE_NEGATIVE);
    effect eDur2 = EffectVisualEffect(VFX_DUR_CESSATE_POSITIVE);

    effect eLink = EffectLinkEffects(eDamage, eDur2);

    effect eLink2 = EffectLinkEffects(eVisFear, eFear);
    eLink = EffectLinkEffects(eLink, eDur);

    //Meta Magic
    if(GetMetaMagicFeat() == METAMAGIC_EXTEND)
    {
       nLevel *= 2;
    }
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eLOS, OBJECT_SELF);
    //Determine enemies in the radius around the bard
    oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, GetLocation(OBJECT_SELF));
    while (GetIsObjectValid(oTarget))
    {
        if (spellsIsTarget(oTarget, SPELL_TARGET_SELECTIVEHOSTILE, OBJECT_SELF) && oTarget != OBJECT_SELF)
        {
           SignalEvent(oTarget, EventSpellCastAt(OBJECT_SELF, SPELL_WAR_CRY));
           //Make SR and Will saves
           if(!MyResistSpell(OBJECT_SELF, oTarget)  && !MySavingThrow(SAVING_THROW_WILL, oTarget, GetSpellSaveDC(), SAVING_THROW_TYPE_FEAR))
            {
                DelayCommand(0.01, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLink2, oTarget, RoundsToSeconds(4)));
            }
        }
        oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, GetLocation(OBJECT_SELF));
    }
    //Apply bonus and VFX effects to bard.
    RemoveSpellEffects(GetSpellId(),OBJECT_SELF,OBJECT_SELF);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, OBJECT_SELF);
    DelayCommand(0.01, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLink, OBJECT_SELF, RoundsToSeconds(nLevel)));
    // Same delay, scheduled after the apply, so the witness is in place first.
    DelayCommand(0.01, BPool_SpellAttack(OBJECT_SELF, BPOOL_SRC_WARCRY, nAttack, RoundsToSeconds(nLevel)));
    SignalEvent(OBJECT_SELF, EventSpellCastAt(OBJECT_SELF, SPELL_WAR_CRY, FALSE));
}
