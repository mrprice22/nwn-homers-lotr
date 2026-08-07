//::///////////////////////////////////////////////
//:: Bless
//:: x0_s0_divfav.nss
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
+1 bonus to attack and damage for every three
caster levels (+1 to max +5)  \
NOTE: Official rules say +6, we can only go to +5
 Duration: 1 turn
*/
//:://////////////////////////////////////////////
//:: Created By: Brent Knowles
//:: Created On: July 15, 2002
//:://////////////////////////////////////////////
//:: VFX Pass By:
//:: MODULE FORK, 2026-08-06 (roadmap: spell-ab-prowess-stack).
//:: Divine Favor's attack bonus (+1 per three caster levels, capped at +5) is
//:: registered with the per-creature bonus ledger instead of being linked as an
//:: effect: same-type attack-bonus effects do not stack, so even the +5 version
//:: gave a Legendary Prowess holder nothing at all. The damage half stays a
//:: linked effect (magical damage, and different damage types already stack)
//:: and keeps the duration VFX company as the ledger's witness.
#include "NW_I0_SPELLS"

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
    int nMetaMagic = GetMetaMagicFeat();
    effect eVis = EffectVisualEffect(VFX_IMP_HEAD_HOLY);


    effect eImpact = EffectVisualEffect(VFX_FNF_LOS_HOLY_30);

    int nScale = (GetCasterLevel(OBJECT_SELF) / 3);
    // * must fall between +1 and +5
    if (nScale < 1)
        nScale = 1;
    else
    if (nScale > 5)
        nScale = 5;
    // * determine the damage bonus to apply
    // The attack half is pooled - see the header note.
    effect eDamage = EffectDamageIncrease(nScale, DAMAGE_TYPE_MAGICAL);


    effect eDur = EffectVisualEffect(VFX_DUR_CESSATE_POSITIVE);
    effect eLink = EffectLinkEffects(eDamage, eDur);

    int nDuration = 1; // * Duration 1 turn
    if ( nMetaMagic == METAMAGIC_EXTEND )
    {
        nDuration = nDuration * 2;
    }

    //Apply Impact
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, eImpact, GetSpellTargetLocation());
    oTarget = OBJECT_SELF;

    //Fire spell cast at event for target
    SignalEvent(oTarget, EventSpellCastAt(OBJECT_SELF, 414, FALSE));
    //Apply VFX impact and bonus effects
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oTarget);
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLink, oTarget, TurnsToSeconds(nDuration));
    BPool_SpellAttack(oTarget, BPOOL_SRC_DIVFAV, nScale, TurnsToSeconds(nDuration));

}

