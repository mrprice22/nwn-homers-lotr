// legfeat_atk_inc.nss - attacker-side legendary feat hooks.
//
// Called from devcrit_atk.nss, the server-wide NWNX Damage ATTACK script,
// which is the only place in the module where the RESULT of an attack is
// visible to script at all. Four feats live here:
//
//   Legendary Wrath      - +1 damage per 5% of the attacker's missing health
//   Legendary Quarry     - +50% damage to a favoured enemy below half health
//   Legendary Sundering  - -3 to the target's AC per landed hit, stacking 3
//   Legendary Reaping    - +2 attack / +2 damage per kill, stacking 5
//
// ###########################################################################
// # ENTRY IS GATED BY ONE GetLocalInt IN THE CALLER. Nothing in this file    #
// # runs for a character who holds none of these feats, and that gate        #
// # (LEGFEAT_ATK_VAR, set by LegFeat_ArmHooks) is what keeps four feats held #
// # by a handful of level-60s off the hot path of every attack on the        #
// # server. Never call in here without it.                                   #
// ###########################################################################
//
// THE DAMAGE STRUCT IS READ-ONLY HERE. devcrit_atk owns it: it modifies its
// own copy and calls NWNX_Damage_SetAttackEventData once, at the end, on the
// critical path only. If this file also wrote to the struct, a bonus added
// here would be silently dropped on every non-critical hit (devcrit returns
// early and never sets), and double-counted on criticals. So these feats add
// their damage as a separate EffectDamage instead - which is also the honest
// rendering: the combat log shows the feat's contribution on its own line.

#include "nwnx_damage"
#include "legfeat_ids_inc"

// Set by LegFeat_ArmHooks on any character holding an attacker-side hook feat,
// and read by devcrit_atk.nss once per attack. It is declared here rather than
// in legfeat_inc.nss so that the hot-path caller can include this file alone.
const string LEGFEAT_ATK_VAR    = "legfeat_atk";

const string LEGFEAT_SUNDER_TAG = "LEGFEAT_SUNDER";
const string LEGFEAT_SUNDER_AMT = "legfeat_sunder_amt";
const string LEGFEAT_SUNDER_GEN = "legfeat_sunder_gen";
const float  LEGFEAT_SUNDER_DUR = 18.0;
const int    LEGFEAT_SUNDER_STEP = 3;
const int    LEGFEAT_SUNDER_MAX = 9;      // three stacks of three

const string LEGFEAT_REAP_TAG   = "LEGFEAT_REAP";
const string LEGFEAT_REAP_AMT   = "legfeat_reap_amt";
const string LEGFEAT_REAP_GEN   = "legfeat_reap_gen";
const float  LEGFEAT_REAP_DUR   = 12.0;
const int    LEGFEAT_REAP_STEP  = 2;
const int    LEGFEAT_REAP_MAX   = 10;     // five stacks of two

const int    LEGFEAT_WRATH_MAX  = 20;

// Damage the engine has already resolved for this attack. Fields that were not
// dealt come back as -1, NOT 0 (the trap devcrit_atk documents), so every field
// is tested before it is added.
int LegFeatAtk_Total(struct NWNX_Damage_AttackEventData data)
{
    int nTotal = 0;
    if (data.iBase        > 0) nTotal += data.iBase;
    if (data.iBludgeoning > 0) nTotal += data.iBludgeoning;
    if (data.iPierce      > 0) nTotal += data.iPierce;
    if (data.iSlash       > 0) nTotal += data.iSlash;
    if (data.iMagical     > 0) nTotal += data.iMagical;
    if (data.iAcid        > 0) nTotal += data.iAcid;
    if (data.iCold        > 0) nTotal += data.iCold;
    if (data.iDivine      > 0) nTotal += data.iDivine;
    if (data.iElectrical  > 0) nTotal += data.iElectrical;
    if (data.iFire        > 0) nTotal += data.iFire;
    if (data.iNegative    > 0) nTotal += data.iNegative;
    if (data.iPositive    > 0) nTotal += data.iPositive;
    if (data.iSonic       > 0) nTotal += data.iSonic;
    return nTotal;
}

// The weapon that swung, by the same rule devcrit_atk uses: attack types 1 and
// 6 are the right hand, 2 is the left, and creature/unarmed attacks have no
// weapon object at all.
object LegFeatAtk_Weapon(object oAttacker, int nWeaponAttackType)
{
    if (nWeaponAttackType == 1 || nWeaponAttackType == 6)
        return GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oAttacker);
    if (nWeaponAttackType == 2)
        return GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oAttacker);
    return OBJECT_INVALID;
}

// Physical damage type of the weapon in hand, from baseitems.2da. Fists,
// claws and bites are bludgeoning. Same table devcrit_atk reads, and the same
// reason: these bonuses are typed physical on purpose, so heavy damage
// reduction eats part of them.
int LegFeatAtk_DamageType(object oWeapon)
{
    if (GetIsObjectValid(oWeapon))
    {
        int n = StringToInt(Get2DAString("baseitems", "WeaponType",
                                         GetBaseItemType(oWeapon)));
        if (n == 1) return DAMAGE_TYPE_PIERCING;
        if (n == 3 || n == 4) return DAMAGE_TYPE_SLASHING;
    }
    return DAMAGE_TYPE_BLUDGEONING;
}

// Percentage of the creature's health that is gone, 0-100.
int LegFeatAtk_MissingPercent(object oCreature)
{
    int nMax = GetMaxHitPoints(oCreature);
    if (nMax <= 0) return 0;
    int nCur = GetCurrentHitPoints(oCreature);
    if (nCur >= nMax) return 0;
    if (nCur < 0) nCur = 0;
    return 100 - ((nCur * 100) / nMax);
}

// Does the attacker have the Favoured Enemy feat matching this target's race?
// There is no GetIsFavoredEnemy(), and the ranger's own bonus is engine-side
// and invisible to script, so the racial type has to be mapped to the feat by
// hand. Racial types with no favoured-enemy feat (ooze, and the humanoid
// catch-alls the module does not use) simply never match.
int LegFeatAtk_IsFavoured(object oAttacker, object oTarget)
{
    int nFeat = -1;
    switch (GetRacialType(oTarget))
    {
        case RACIAL_TYPE_DWARF:              nFeat = FEAT_FAVORED_ENEMY_DWARF; break;
        case RACIAL_TYPE_ELF:                nFeat = FEAT_FAVORED_ENEMY_ELF; break;
        case RACIAL_TYPE_GNOME:              nFeat = FEAT_FAVORED_ENEMY_GNOME; break;
        case RACIAL_TYPE_HALFLING:           nFeat = FEAT_FAVORED_ENEMY_HALFLING; break;
        case RACIAL_TYPE_HALFELF:            nFeat = FEAT_FAVORED_ENEMY_HALFELF; break;
        case RACIAL_TYPE_HALFORC:            nFeat = FEAT_FAVORED_ENEMY_HALFORC; break;
        case RACIAL_TYPE_HUMAN:              nFeat = FEAT_FAVORED_ENEMY_HUMAN; break;
        case RACIAL_TYPE_ABERRATION:         nFeat = FEAT_FAVORED_ENEMY_ABERRATION; break;
        case RACIAL_TYPE_ANIMAL:             nFeat = FEAT_FAVORED_ENEMY_ANIMAL; break;
        case RACIAL_TYPE_BEAST:              nFeat = FEAT_FAVORED_ENEMY_BEAST; break;
        case RACIAL_TYPE_CONSTRUCT:          nFeat = FEAT_FAVORED_ENEMY_CONSTRUCT; break;
        case RACIAL_TYPE_DRAGON:             nFeat = FEAT_FAVORED_ENEMY_DRAGON; break;
        case RACIAL_TYPE_HUMANOID_GOBLINOID: nFeat = FEAT_FAVORED_ENEMY_GOBLINOID; break;
        case RACIAL_TYPE_HUMANOID_MONSTROUS: nFeat = FEAT_FAVORED_ENEMY_MONSTROUS; break;
        case RACIAL_TYPE_HUMANOID_ORC:       nFeat = FEAT_FAVORED_ENEMY_ORC; break;
        case RACIAL_TYPE_HUMANOID_REPTILIAN: nFeat = FEAT_FAVORED_ENEMY_REPTILIAN; break;
        case RACIAL_TYPE_ELEMENTAL:          nFeat = FEAT_FAVORED_ENEMY_ELEMENTAL; break;
        case RACIAL_TYPE_FEY:                nFeat = FEAT_FAVORED_ENEMY_FEY; break;
        case RACIAL_TYPE_GIANT:              nFeat = FEAT_FAVORED_ENEMY_GIANT; break;
        case RACIAL_TYPE_MAGICAL_BEAST:      nFeat = FEAT_FAVORED_ENEMY_MAGICAL_BEAST; break;
        case RACIAL_TYPE_OUTSIDER:           nFeat = FEAT_FAVORED_ENEMY_OUTSIDER; break;
        case RACIAL_TYPE_SHAPECHANGER:       nFeat = FEAT_FAVORED_ENEMY_SHAPECHANGER; break;
        case RACIAL_TYPE_UNDEAD:             nFeat = FEAT_FAVORED_ENEMY_UNDEAD; break;
        case RACIAL_TYPE_VERMIN:             nFeat = FEAT_FAVORED_ENEMY_VERMIN; break;
    }
    return nFeat >= 0 && GetHasFeat(nFeat, oAttacker);
}

// Strip our own tagged effects off a creature. Used before re-applying a
// stack, because an effect's magnitude cannot be read back - the running total
// is kept in a local int and the effect is rebuilt from it.
void LegFeatAtk_StripTag(object oCreature, string sTag)
{
    effect e = GetFirstEffect(oCreature);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == sTag) RemoveEffect(oCreature, e);
        e = GetNextEffect(oCreature);
    }
}

// Clear a stack counter, but only if no later hit has refreshed it. Each
// application bumps a generation counter and schedules this with the
// generation it saw; a refresh makes the older scheduled clear a no-op. Without
// that, the second hit's 18 seconds would be cut short by the first hit's
// expiry.
void LegFeatAtk_ExpireStack(object oCreature, string sAmtVar, string sGenVar,
                            string sTag, int nGen)
{
    if (GetLocalInt(oCreature, sGenVar) != nGen) return;
    DeleteLocalInt(oCreature, sAmtVar);
    LegFeatAtk_StripTag(oCreature, sTag);
}

void LegFeatAtk_OnAttack(struct NWNX_Damage_AttackEventData data)
{
    object oAttacker = OBJECT_SELF;
    object oTarget   = data.oTarget;
    if (!GetIsObjectValid(oTarget)) return;

    // Legendary Reaping keys off the kill, not off damage, so it is checked
    // before the "did this land" test - a killing blow has already landed.
    if (data.bKillingBlow && GetHasFeat(FEAT_LEGENDARY_REAPING, oAttacker))
    {
        int nAmt = GetLocalInt(oAttacker, LEGFEAT_REAP_AMT) + LEGFEAT_REAP_STEP;
        if (nAmt > LEGFEAT_REAP_MAX) nAmt = LEGFEAT_REAP_MAX;

        LegFeatAtk_StripTag(oAttacker, LEGFEAT_REAP_TAG);
        SetLocalInt(oAttacker, LEGFEAT_REAP_AMT, nAmt);
        int nGen = GetLocalInt(oAttacker, LEGFEAT_REAP_GEN) + 1;
        SetLocalInt(oAttacker, LEGFEAT_REAP_GEN, nGen);

        effect eAB = TagEffect(EffectAttackIncrease(nAmt), LEGFEAT_REAP_TAG);
        effect eDm = TagEffect(EffectDamageIncrease(nAmt, DAMAGE_TYPE_BLUDGEONING),
                               LEGFEAT_REAP_TAG);
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eAB, oAttacker,
                            LEGFEAT_REAP_DUR);
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eDm, oAttacker,
                            LEGFEAT_REAP_DUR);
        DelayCommand(LEGFEAT_REAP_DUR + 0.1,
                     LegFeatAtk_ExpireStack(oAttacker, LEGFEAT_REAP_AMT,
                                            LEGFEAT_REAP_GEN, LEGFEAT_REAP_TAG,
                                            nGen));
    }

    // Everything below is "this attack landed". The attack RESULT enum is not
    // used for that test on purpose: devcrit_atk needs two specific values out
    // of it, but "did any damage get through" is answered exactly by the damage
    // the engine already resolved, and that cannot drift if the enum does.
    int nDealt = LegFeatAtk_Total(data);
    if (nDealt <= 0) return;

    object oWeapon = LegFeatAtk_Weapon(oAttacker, data.iWeaponAttackType);
    int nDmgType   = LegFeatAtk_DamageType(oWeapon);

    // --- Legendary Wrath: the closer to death, the harder the blow ---------
    if (GetHasFeat(FEAT_LEGENDARY_WRATH, oAttacker))
    {
        int nBonus = LegFeatAtk_MissingPercent(oAttacker) / 5;
        if (nBonus > LEGFEAT_WRATH_MAX) nBonus = LEGFEAT_WRATH_MAX;
        if (nBonus > 0)
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                                EffectDamage(nBonus, nDmgType), oTarget);
    }

    // --- Legendary Quarry: finish what you hunted --------------------------
    if (GetHasFeat(FEAT_LEGENDARY_QUARRY, oAttacker)
        && GetCurrentHitPoints(oTarget) * 2 <= GetMaxHitPoints(oTarget)
        && LegFeatAtk_IsFavoured(oAttacker, oTarget))
    {
        int nBonus = nDealt / 2;
        if (nBonus > 0)
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                                EffectDamage(nBonus, nDmgType), oTarget);
    }

    // --- Legendary Sundering: ruin the armour ------------------------------
    //
    // The cap is the design's own: never more than the armour and shield the
    // target is actually wearing are worth, ignoring enchantment
    // (GetItemACValue returns the BASE armour value). An unarmoured target has
    // nothing to sunder, which is intended - it is an armour-shredding feat,
    // not a universal AC debuff.
    if (GetHasFeat(FEAT_LEGENDARY_SUNDERING, oAttacker))
    {
        int nCap = GetItemACValue(GetItemInSlot(INVENTORY_SLOT_CHEST, oTarget))
                 + GetItemACValue(GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oTarget));
        if (nCap > LEGFEAT_SUNDER_MAX) nCap = LEGFEAT_SUNDER_MAX;

        if (nCap > 0)
        {
            int nAmt = GetLocalInt(oTarget, LEGFEAT_SUNDER_AMT)
                     + LEGFEAT_SUNDER_STEP;
            if (nAmt > nCap) nAmt = nCap;

            LegFeatAtk_StripTag(oTarget, LEGFEAT_SUNDER_TAG);
            SetLocalInt(oTarget, LEGFEAT_SUNDER_AMT, nAmt);
            int nGen = GetLocalInt(oTarget, LEGFEAT_SUNDER_GEN) + 1;
            SetLocalInt(oTarget, LEGFEAT_SUNDER_GEN, nGen);

            effect eAC = TagEffect(EffectACDecrease(nAmt, AC_DODGE_BONUS),
                                   LEGFEAT_SUNDER_TAG);
            ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eAC, oTarget,
                                LEGFEAT_SUNDER_DUR);
            DelayCommand(LEGFEAT_SUNDER_DUR + 0.1,
                         LegFeatAtk_ExpireStack(oTarget, LEGFEAT_SUNDER_AMT,
                                                LEGFEAT_SUNDER_GEN,
                                                LEGFEAT_SUNDER_TAG, nGen));
        }
    }
}
