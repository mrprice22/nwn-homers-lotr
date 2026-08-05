//::///////////////////////////////////////////////
//:: Bard Song
//:: nw_s2_bardsong
//:://////////////////////////////////////////////
/*
    Homer's LotR custom Bard Song override.

    NOTE ON RESREF: the Bard Song feat's spell (spells.2da row 411
    "Bards_Song") has ImpactScript NW_S2_BardSong - bard song is core game
    content, so it uses the nw_ prefix (not the HotU x0_ or x2_ prefix). This
    file MUST be named nw_s2_bardsong to actually replace the ability. (Curse
    Song, by contrast, is HotU content and routes to x2_s2_cursesong.)

    Restores the buff/debuff symmetry with this module's customized Curse
    Song (x2_s2_cursesong): a 23-tier ladder keyed on BOTH Perform skill and
    Bard level, extended to Perform 80 / Bard 30. Buffs the bard and nearby
    allies in a colossal-radius sphere.

    Scaling is deliberately CONSERVATIVE relative to Curse Song (roughly half
    of its combat magnitudes) because a party-wide buff is stronger than an
    enemy-side debuff. Curse Song's "sonic damage" column is reinterpreted
    here as temporary hit points, softened at the very top (98 -> 60).

    Duration mirrors Curse Song: base 15 rounds, Lingering Song (feat 424)
    +15 rounds, Lasting Impression (feat 870) x15.
*/
//:://////////////////////////////////////////////

#include "x2_i0_spells"
#include "x2_inc_itemprop"

void main()
{
    if (!GetHasFeat(FEAT_BARD_SONGS, OBJECT_SELF))
    {
        FloatingTextStrRefOnCreature(85587, OBJECT_SELF); // no more bardsong uses left
        return;
    }

    if (GetHasEffect(EFFECT_TYPE_SILENCE, OBJECT_SELF))
    {
        FloatingTextStrRefOnCreature(85764, OBJECT_SELF); // not useable when silenced
        return;
    }

    // The Thirteenth Ent (roadmap: thirteenth-ent): Leaflock's two-stage
    // concert answers the Bard Song feat. Listener only -- it never changes
    // the song itself, and no-ops unless this bard is mid-concert.
    ExecuteScript("q_ent_song", OBJECT_SELF);

    //Declare major variables
    int nLevel   = GetLevelByClass(CLASS_TYPE_BARD);
    int nPerform = GetSkillRank(SKILL_PERFORM);
    int nDuration = 15;

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

    //Lasting Impression multiplies, Lingering Song adds (mirrors Curse Song).
    if (GetHasFeat(870)) // lasting impression
    {
        nDuration *= 15;
    }
    if (GetHasFeat(424)) // lingering song
    {
        nDuration += 15;
    }

    if (nPerform >= 80 && nLevel >= 30)
    {
        nAttack = 6; nDamage = 6; nWill = 4; nFort = 4; nReflex = 4; nHP = 60; nAC = 6; nSkill = 12;
    }
    else if (nPerform >= 75 && nLevel >= 29)
    {
        nAttack = 6; nDamage = 5; nWill = 4; nFort = 4; nReflex = 4; nHP = 52; nAC = 5; nSkill = 11;
    }
    else if (nPerform >= 60 && nLevel >= 28)
    {
        nAttack = 5; nDamage = 5; nWill = 4; nFort = 4; nReflex = 4; nHP = 46; nAC = 5; nSkill = 10;
    }
    else if (nPerform >= 55 && nLevel >= 27)
    {
        nAttack = 5; nDamage = 5; nWill = 4; nFort = 4; nReflex = 4; nHP = 44; nAC = 5; nSkill = 10;
    }
    else if (nPerform >= 50 && nLevel >= 26)
    {
        nAttack = 5; nDamage = 5; nWill = 3; nFort = 3; nReflex = 3; nHP = 42; nAC = 4; nSkill = 9;
    }
    else if (nPerform >= 45 && nLevel >= 25)
    {
        nAttack = 5; nDamage = 5; nWill = 3; nFort = 3; nReflex = 3; nHP = 40; nAC = 4; nSkill = 9;
    }
    else if (nPerform >= 40 && nLevel >= 24)
    {
        nAttack = 4; nDamage = 4; nWill = 3; nFort = 2; nReflex = 2; nHP = 36; nAC = 4; nSkill = 8;
    }
    else if (nPerform >= 35 && nLevel >= 23)
    {
        nAttack = 4; nDamage = 4; nWill = 3; nFort = 2; nReflex = 2; nHP = 34; nAC = 4; nSkill = 8;
    }
    else if (nPerform >= 30 && nLevel >= 22)
    {
        nAttack = 4; nDamage = 4; nWill = 3; nFort = 2; nReflex = 2; nHP = 32; nAC = 3; nSkill = 7;
    }
    else if (nPerform >= 25 && nLevel >= 21)
    {
        nAttack = 4; nDamage = 4; nWill = 3; nFort = 2; nReflex = 2; nHP = 30; nAC = 3; nSkill = 7;
    }
    else if (nPerform >= 20 && nLevel >= 20)
    {
        nAttack = 4; nDamage = 4; nWill = 3; nFort = 2; nReflex = 2; nHP = 28; nAC = 3; nSkill = 6;
    }
    else if (nPerform >= 15 && nLevel >= 19)
    {
        nAttack = 4; nDamage = 4; nWill = 2; nFort = 2; nReflex = 2; nHP = 26; nAC = 3; nSkill = 6;
    }
    else if (nPerform >= 12 && nLevel >= 18)
    {
        nAttack = 3; nDamage = 4; nWill = 2; nFort = 2; nReflex = 2; nHP = 24; nAC = 3; nSkill = 5;
    }
    else if (nPerform >= 10 && nLevel >= 17)
    {
        nAttack = 3; nDamage = 4; nWill = 2; nFort = 2; nReflex = 2; nHP = 22; nAC = 3; nSkill = 5;
    }
    else if (nPerform >= 9 && nLevel >= 16)
    {
        nAttack = 3; nDamage = 3; nWill = 2; nFort = 2; nReflex = 2; nHP = 20; nAC = 2; nSkill = 4;
    }
    else if (nPerform >= 8 && nLevel >= 15)
    {
        nAttack = 3; nDamage = 3; nWill = 2; nFort = 1; nReflex = 1; nHP = 16; nAC = 2; nSkill = 3;
    }
    else if (nPerform >= 7 && nLevel >= 14)
    {
        nAttack = 3; nDamage = 3; nWill = 1; nFort = 1; nReflex = 1; nHP = 14; nAC = 2; nSkill = 2;
    }
    else if (nPerform >= 6 && nLevel >= 12)
    {
        nAttack = 2; nDamage = 3; nWill = 1; nFort = 1; nReflex = 1; nHP = 10; nAC = 2; nSkill = 2;
    }
    else if (nPerform >= 5 && nLevel >= 8)
    {
        nAttack = 2; nDamage = 3; nWill = 1; nFort = 1; nReflex = 1; nHP = 8; nAC = 1; nSkill = 1;
    }
    else if (nPerform >= 4 && nLevel >= 6)
    {
        nAttack = 2; nDamage = 3; nWill = 1; nFort = 1; nReflex = 1; nHP = 4; nAC = 1; nSkill = 1;
    }
    else if (nPerform >= 2 && nLevel >= 3)
    {
        nAttack = 1; nDamage = 2; nWill = 1; nFort = 1; nReflex = 0; nHP = 0; nAC = 0; nSkill = 1;
    }
    else if (nPerform >= 1 && nLevel >= 2)
    {
        nAttack = 1; nDamage = 2; nWill = 1; nFort = 0; nReflex = 0; nHP = 0; nAC = 0; nSkill = 0;
    }
    else if (nPerform >= 1 && nLevel >= 1)
    {
        nAttack = 1; nDamage = 1; nWill = 0; nFort = 0; nReflex = 0; nHP = 0; nAC = 0; nSkill = 0;
    }

    effect eVis = EffectVisualEffect(VFX_DUR_BARD_SONG);

    eAttack = EffectAttackIncrease(nAttack);
    // EffectDamageIncrease takes a DAMAGE_BONUS_* constant, NOT a flat int: raw
    // values >5 become dice (6 = 1d4, 8 = 1d8, 10 = 2d6). Map the intended flat
    // amount to the correct constant (6 -> DAMAGE_BONUS_6 = 16, etc.) so the top
    // tier delivers flat +6 instead of 1d4.
    eDamage = EffectDamageIncrease(nDamage > 0 ? IPGetDamageBonusConstantFromNumber(nDamage) : nDamage, DAMAGE_TYPE_BLUDGEONING);
    effect eLink = EffectLinkEffects(eAttack, eDamage);

    if (nWill > 0)
    {
        eWill = EffectSavingThrowIncrease(SAVING_THROW_WILL, nWill);
        eLink = EffectLinkEffects(eLink, eWill);
    }
    if (nFort > 0)
    {
        eFort = EffectSavingThrowIncrease(SAVING_THROW_FORT, nFort);
        eLink = EffectLinkEffects(eLink, eFort);
    }
    if (nReflex > 0)
    {
        eReflex = EffectSavingThrowIncrease(SAVING_THROW_REFLEX, nReflex);
        eLink = EffectLinkEffects(eLink, eReflex);
    }
    if (nAC > 0)
    {
        eAC = EffectACIncrease(nAC, AC_DODGE_BONUS);
        eLink = EffectLinkEffects(eLink, eAC);
    }
    if (nSkill > 0)
    {
        eSkill = EffectSkillIncrease(SKILL_ALL_SKILLS, nSkill);
        eLink = EffectLinkEffects(eLink, eSkill);
    }
    if (nHP > 0)
    {
        // Temp HP kept as a SEPARATE, unlinked extraordinary effect (mirrors
        // nifty_i0_bard) to avoid the link/duration interaction.
        eHP = EffectTemporaryHitpoints(nHP);
        eHP = ExtraordinaryEffect(eHP);
    }

    effect eDur = EffectVisualEffect(VFX_DUR_CESSATE_POSITIVE);
    eLink = EffectLinkEffects(eLink, eDur);
    eLink = ExtraordinaryEffect(eLink);

    effect eImpact = EffectVisualEffect(VFX_IMP_HEAD_SONIC);
    effect eFNF = EffectVisualEffect(VFX_FNF_LOS_NORMAL_30);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, eFNF, GetLocation(OBJECT_SELF));

    object oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, GetLocation(OBJECT_SELF));
    while (GetIsObjectValid(oTarget))
    {
        if (!GetHasSpellEffect(GetSpellId(), oTarget))
        {
            if (oTarget == OBJECT_SELF)
            {
                effect eLinkBard = EffectLinkEffects(eLink, eVis);
                eLinkBard = ExtraordinaryEffect(eLinkBard);
                ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLinkBard, oTarget, RoundsToSeconds(nDuration));
                if (nHP > 0)
                    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eHP, oTarget, RoundsToSeconds(nDuration));
            }
            else if (GetIsFriend(oTarget))
            {
                ApplyEffectToObject(DURATION_TYPE_INSTANT, eImpact, oTarget);
                ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eLink, oTarget, RoundsToSeconds(nDuration));
                if (nHP > 0)
                    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eHP, oTarget, RoundsToSeconds(nDuration));
            }
        }
        oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, GetLocation(OBJECT_SELF));
    }

    DecrementRemainingFeatUses(OBJECT_SELF, FEAT_BARD_SONGS);
}
