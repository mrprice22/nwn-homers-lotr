//::///////////////////////////////////////////////
//:: Curse Song
//:: X2_S2_CurseSong
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    This spells applies penalties to all of the
    bard's enemies within 30ft for a set duration of
    10 rounds.
*/
//:://////////////////////////////////////////////
//:: Created By: Andrew Nobbs
//:: Created On: May 16, 2003
//:://////////////////////////////////////////////
//:: Last Updated By: Andrew Nobbs May 20, 2003

#include "x2_i0_spells"
#include "x2_inc_itemprop"

void main()
{

   if (!GetHasFeat(FEAT_BARD_SONGS, OBJECT_SELF))
   {
        FloatingTextStrRefOnCreature(85587,OBJECT_SELF); // no more bardsong uses left
        return;
   }

    if (GetHasEffect(EFFECT_TYPE_SILENCE,OBJECT_SELF))
    {
        FloatingTextStrRefOnCreature(85764,OBJECT_SELF); // not useable when silenced
        return;
    }


    //Declare major variables
    int nLevel = GetLevelByClass(CLASS_TYPE_BARD);
    int nRanks = GetSkillRank(SKILL_PERFORM);
    int nPerform = nRanks;
    int nDuration = 15; //+ nChr;

    effect eAttack;
    effect eDamage;
    effect eWill;
    effect eFort;
    effect eReflex;
    effect eHP;
    effect eAC;
    effect eSkill;

    int nAttack;
    int nDamage;
    int nWill;
    int nFort;
    int nReflex;
    int nHP;
    int nAC;
    int nSkill;
    //Check to see if the caster has Lasting Impression and increase duration.
    if(GetHasFeat(870))
    {
        nDuration *= 15;
    }

    if(GetHasFeat(424)) // lingering song
    {
        nDuration += 15;
    }

    if(nPerform >= 80 && nLevel >= 30)
    {
        nAttack = 15;
        nDamage = 10;
        nWill = 7;
        nFort = 7;
        nReflex = 7;
        nHP = 98;
        nAC = 15;
        nSkill = 18;
    }
    else if(nPerform >= 75 && nLevel >= 29)
    {
        nAttack = 13;
        nDamage = 8;
        nWill = 5;
        nFort = 5;
        nReflex = 5;
        nHP = 56;
        nAC = 10;
        nSkill = 17;
    }
    else if(nPerform >= 60 && nLevel >= 28)
    {
        nAttack = 10;
        nDamage = 6;
        nWill = 4;
        nFort = 4;
        nReflex = 4;
        nHP = 44;
        nAC = 8;
        nSkill = 16;
    }
    else if(nPerform >= 55 && nLevel >= 27)
    {
        nAttack = 8;
        nDamage = 6;
        nWill = 4;
        nFort = 4;
        nReflex = 4;
        nHP = 42;
        nAC = 8;
        nSkill = 15;
    }
    else if(nPerform >= 50 && nLevel >= 26)
    {
        nAttack = 7;
        nDamage = 6;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 40;
        nAC = 6;
        nSkill = 14;
    }
    else if(nPerform >= 45 && nLevel >= 25)
    {
        nAttack = 7;
        nDamage = 5;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 38;
        nAC = 6;
        nSkill = 13;
    }
    else if(nPerform >= 40 && nLevel >= 24)
    {
        nAttack = 6;
        nDamage = 5;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 36;
        nAC = 5;
        nSkill = 12;
    }
    else if(nPerform >= 35 && nLevel >= 23)
    {
        nAttack = 6;
        nDamage = 5;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 34;
        nAC = 5;
        nSkill = 11;
    }
    else if(nPerform >= 30 && nLevel >= 22)
    {
        nAttack = 6;
        nDamage = 5;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 32;
        nAC = 5;
        nSkill = 10;
    }
    else if(nPerform >= 25 && nLevel >= 21)
    {
        nAttack = 6;
        nDamage = 5;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 30;
        nAC = 5;
        nSkill = 9;
    }
    else if(nPerform >= 20 && nLevel >= 20)
    {
        nAttack = 6;
        nDamage = 5;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 28;
        nAC = 5;
        nSkill = 8;
    }
    else if(nPerform >= 15 && nLevel >= 19)
    {
        nAttack = 5;
        nDamage = 4;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 26;
        nAC = 5;
        nSkill = 7;
    }
    else if(nPerform >= 12 && nLevel >= 18)
    {
        nAttack = 5;
        nDamage = 4;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 24;
        nAC = 5;
        nSkill = 6;
    }
    else if(nPerform >= 10 && nLevel >= 17)
    {
        nAttack = 5;
        nDamage = 4;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 22;
        nAC = 5;
        nSkill = 5;
    }
    else if(nPerform >= 9 && nLevel >= 16)
    {
        nAttack = 4;
        nDamage = 4;
        nWill = 3;
        nFort = 2;
        nReflex = 2;
        nHP = 20;
        nAC = 5;
        nSkill = 4;
    }
    else if(nPerform >= 8 && nLevel >= 15)
    {
        nAttack = 4;
        nDamage = 4;
        nWill = 2;
        nFort = 2;
        nReflex = 2;
        nHP = 16;
        nAC = 4;
        nSkill = 3;
    }
    else if(nPerform >= 7 && nLevel >= 14)
    {
        nAttack = 4;
        nDamage = 4;
        nWill = 1;
        nFort = 1;
        nReflex = 1;
        nHP = 16;
        nAC = 3;
        nSkill = 2;
    }
    else if(nPerform >= 6 && nLevel >= 12)
    {
        nAttack = 4;
        nDamage = 3;
        nWill = 1;
        nFort = 1;
        nReflex = 1;
        nHP = 8;
        nAC = 2;
        nSkill = 2;
    }
    else if(nPerform >= 5 && nLevel >= 8)
    {
        nAttack = 3;
        nDamage = 3;
        nWill = 1;
        nFort = 1;
        nReflex = 1;
        nHP = 8;
        nAC = 0;
        nSkill = 1;
    }
    else if(nPerform >= 4 && nLevel >= 6)
    {
        nAttack = 2;
        nDamage = 3;
        nWill = 1;
        nFort = 1;
        nReflex = 1;
        nHP = 0;
        nAC = 0;
        nSkill = 1;
    }
    else if(nPerform >= 2 && nLevel >= 3)
    {
        nAttack = 2;
        nDamage = 3;
        nWill = 1;
        nFort = 1;
        nReflex = 0;
        nHP = 0;
        nAC = 0;
        nSkill = 0;
    }
    else if(nPerform >= 1 && nLevel >= 2)
    {
        nAttack = 1;
        nDamage = 2;
        nWill = 1;
        nFort = 0;
        nReflex = 0;
        nHP = 0;
        nAC = 0;
        nSkill = 0;
    }
    else if(nPerform >= 1 && nLevel >= 1)
    {
        nAttack = 1;
        nDamage = 1;
        nWill = 0;
        nFort = 0;
        nReflex = 0;
        nHP = 0;
        nAC = 0;
        nSkill = 0;
    }
    effect eVis = EffectVisualEffect(VFX_IMP_DOOM);

    eAttack = EffectAttackDecrease(nAttack);
    // EffectDamageDecrease uses the same DAMAGE_BONUS_* encoding as
    // EffectDamageIncrease: raw values >5 become dice (6 = 1d4, 8 = 1d8,
    // 10 = 2d6). Map the intended flat penalty to the correct constant so the
    // top tiers deliver flat -6/-8/-10 instead of dice.
    eDamage = EffectDamageDecrease(nDamage > 0 ? IPGetDamageBonusConstantFromNumber(nDamage) : nDamage, DAMAGE_TYPE_SLASHING);
    effect eLink = EffectLinkEffects(eAttack, eDamage);

    if(nWill > 0)
    {
        eWill = EffectSavingThrowDecrease(SAVING_THROW_WILL, nWill);
        eLink = EffectLinkEffects(eLink, eWill);
    }
    if(nFort > 0)
    {
        eFort = EffectSavingThrowDecrease(SAVING_THROW_FORT, nFort);
        eLink = EffectLinkEffects(eLink, eFort);
    }
    if(nReflex > 0)
    {
        eReflex = EffectSavingThrowDecrease(SAVING_THROW_REFLEX, nReflex);
        eLink = EffectLinkEffects(eLink, eReflex);
    }
    if(nHP > 0)
    {
        //SpeakString("HP Bonus " + IntToString(nHP));
        eHP = EffectDamage(nHP, DAMAGE_TYPE_SONIC, DAMAGE_POWER_NORMAL);
//        eLink = EffectLinkEffects(eLink, eHP);
    }
    if(nAC > 0)
    {
        eAC = EffectACDecrease(nAC, AC_DODGE_BONUS);
        eLink = EffectLinkEffects(eLink, eAC);
    }
    if(nSkill > 0)
    {
        eSkill = EffectSkillDecrease(SKILL_ALL_SKILLS, nSkill);
        eLink = EffectLinkEffects(eLink, eSkill);
    }
    effect eDur  = EffectVisualEffect(VFX_DUR_CESSATE_NEGATIVE);
    effect eDur2 = EffectVisualEffect(507);
    eLink = EffectLinkEffects(eLink, eDur);

    effect eImpact = EffectVisualEffect(VFX_IMP_HEAD_SONIC);
    effect eFNF = EffectVisualEffect(VFX_FNF_LOS_EVIL_30);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, eFNF, GetLocation(OBJECT_SELF));

    object oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, GetLocation(OBJECT_SELF));

    eHP = ExtraordinaryEffect(eHP);
    eLink = ExtraordinaryEffect(eLink);

    if(!GetHasFeatEffect(871, oTarget)&& !GetHasSpellEffect(GetSpellId(),oTarget))
    {
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eDur2, OBJECT_SELF, RoundsToSeconds(nDuration));
    }
    float fDelay;
    while(GetIsObjectValid(oTarget))
    {
        if(spellsIsTarget(oTarget, SPELL_TARGET_SELECTIVEHOSTILE, OBJECT_SELF))
        {
             // * GZ Oct 2003: If we are deaf, we do not have negative effects from curse song
            if (!GetHasEffect(EFFECT_TYPE_DEAF,oTarget))
            {
                if(!GetHasFeatEffect(871, oTarget)&& !GetHasSpellEffect(GetSpellId(),oTarget))
                {
                    if (nHP > 0)
                    {
                        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_SONIC), oTarget);
                        DelayCommand(0.01, ApplyEffectToObject(DURATION_TYPE_INSTANT, eHP, oTarget));
                    }

                    if (!GetIsDead(oTarget))
                    {
                        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLink, oTarget, RoundsToSeconds(nDuration));
                        DelayCommand(GetRandomDelay(0.1,0.5),ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oTarget));
                   }
                }
            }
            else
            {
                   ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_MAGIC_RESISTANCE_USE), oTarget);
            }
        }

        oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, GetLocation(OBJECT_SELF));
    }
    DecrementRemainingFeatUses(OBJECT_SELF, FEAT_BARD_SONGS);
}
