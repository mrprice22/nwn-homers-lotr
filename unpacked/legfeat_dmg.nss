// legfeat_dmg.nss - defender-side legendary feat hooks: the NWNX Damage DAMAGE
// event script.
//
// Registered PER CHARACTER by LegFeat_ArmHooks, and only on a character holding
// Legendary Bulwark or Legendary Riposte:
//
//     NWNX_Damage_SetDamageEventScript("legfeat_dmg", oPC);
//
// That is the whole reason this is not one more branch in a server-wide
// handler. Everybody else has no damage script at all and pays nothing for
// these two feats. LegFeat_ArmHooks also CLEARS the registration (setting it to
// "") when the last of the two is respecced away - without that, the reduction
// would outlive the feat.
//
// OBJECT_SELF is the CHARACTER TAKING THE DAMAGE; data.oDamager dealt it.
//
//   Legendary Bulwark - flat reduction while a shield is on the arm. It runs
//       here, in the damage event, because that is AFTER the engine has
//       finished applying damage reduction, resistance and immunity: this is
//       the one layer nothing can resist around. It is also why Bulwark can
//       prevent a killing blow, which an OnDamaged approach could not.
//   Legendary Riposte - once per round, a landed melee attack is answered with
//       the character's own weapon damage.

#include "nwnx_damage"
#include "legfeat_ids_inc"

const int    LEGFEAT_BULWARK_REDUCTION = 10;

const string LEGFEAT_RIPOSTE_VAR = "legfeat_riposte";
const float  LEGFEAT_RIPOSTE_CD  = 6.0;   // one round

// A shield on the arm. Declared here rather than pulled in from legfeat_inc:
// this script runs on every point of damage the character takes and has no
// business dragging the pick database and NWNX_Creature in behind it.
int LegFeatDmg_HasShield(object oPC)
{
    int nBase = GetBaseItemType(GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC));
    return nBase == BASE_ITEM_SMALLSHIELD || nBase == BASE_ITEM_LARGESHIELD
        || nBase == BASE_ITEM_TOWERSHIELD;
}

// Reduce the physical fields first, then the elemental ones: a shield stops a
// sword more believably than it stops a fireball, and physical is what the
// character is being hit by nearly all of the time.
struct NWNX_Damage_DamageEventData LegFeatDmg_Bulwark(
    struct NWNX_Damage_DamageEventData data, int nBudget)
{
    if (data.iBludgeoning > 0)
    {
        int nCut = (data.iBludgeoning < nBudget) ? data.iBludgeoning : nBudget;
        data.iBludgeoning -= nCut; nBudget -= nCut;
    }
    if (nBudget > 0 && data.iPierce > 0)
    {
        int nCut = (data.iPierce < nBudget) ? data.iPierce : nBudget;
        data.iPierce -= nCut; nBudget -= nCut;
    }
    if (nBudget > 0 && data.iSlash > 0)
    {
        int nCut = (data.iSlash < nBudget) ? data.iSlash : nBudget;
        data.iSlash -= nCut; nBudget -= nCut;
    }
    if (nBudget > 0 && data.iBase > 0)
    {
        int nCut = (data.iBase < nBudget) ? data.iBase : nBudget;
        data.iBase -= nCut; nBudget -= nCut;
    }
    if (nBudget > 0 && data.iMagical > 0)
    {
        int nCut = (data.iMagical < nBudget) ? data.iMagical : nBudget;
        data.iMagical -= nCut; nBudget -= nCut;
    }
    return data;
}

// What one swing of the character's own weapon is worth: the weapon's dice from
// baseitems.2da plus the Strength modifier. Not the engine's full damage
// calculation - enchantment, specialisation and on-hit properties are all left
// out on purpose, so a riposte answers with the weapon and not with the whole
// build. Bare hands roll a d3 like an unarmed strike.
int LegFeatDmg_WeaponDamage(object oPC)
{
    object oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC);
    int nNum = 1, nDie = 3;
    if (GetIsObjectValid(oWeapon))
    {
        int nBase = GetBaseItemType(oWeapon);
        int n = StringToInt(Get2DAString("baseitems", "NumDice", nBase));
        int d = StringToInt(Get2DAString("baseitems", "DieToRoll", nBase));
        if (n > 0 && d > 0) { nNum = n; nDie = d; }
    }

    int nTotal = 0;
    int i;
    for (i = 0; i < nNum; i++) nTotal += Random(nDie) + 1;

    int nStr = GetAbilityModifier(ABILITY_STRENGTH, oPC);
    nTotal += nStr;
    return (nTotal > 1) ? nTotal : 1;
}

int LegFeatDmg_PhysicalType(object oPC)
{
    object oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC);
    if (GetIsObjectValid(oWeapon))
    {
        int n = StringToInt(Get2DAString("baseitems", "WeaponType",
                                         GetBaseItemType(oWeapon)));
        if (n == 1) return DAMAGE_TYPE_PIERCING;
        if (n == 3 || n == 4) return DAMAGE_TYPE_SLASHING;
    }
    return DAMAGE_TYPE_BLUDGEONING;
}

void main()
{
    object oPC = OBJECT_SELF;
    struct NWNX_Damage_DamageEventData data = NWNX_Damage_GetDamageEventData();
    object oDamager = data.oDamager;

    // --- Legendary Bulwark -------------------------------------------------
    if (GetHasFeat(FEAT_LEGENDARY_BULWARK, oPC)
        && LegFeatDmg_HasShield(oPC))
    {
        data = LegFeatDmg_Bulwark(data, LEGFEAT_BULWARK_REDUCTION);
        NWNX_Damage_SetDamageEventData(data);
    }

    // --- Legendary Riposte -------------------------------------------------
    //
    // Melee only, and only from something that can be struck back: the damager
    // has to be a creature standing next to the character. Spell damage, traps
    // and archers all arrive through this same event, and none of them can be
    // answered with a sword.
    if (!GetHasFeat(FEAT_LEGENDARY_RIPOSTE, oPC)) return;
    if (!GetIsObjectValid(oDamager) || oDamager == oPC) return;
    if (GetObjectType(oDamager) != OBJECT_TYPE_CREATURE) return;
    if (data.iSpellId != -1) return;                  // not a weapon blow
    if (GetDistanceBetween(oPC, oDamager) > 3.5) return;

    // Once per round, as a flag cleared by a delayed command. The module's
    // clock functions (GetTimeHour and friends) run on GAME time, which is
    // roughly twenty times faster than the real second this cooldown is
    // measured in, so a timestamp read from them would expire almost at once.
    if (GetLocalInt(oPC, LEGFEAT_RIPOSTE_VAR)) return;
    SetLocalInt(oPC, LEGFEAT_RIPOSTE_VAR, TRUE);
    DelayCommand(LEGFEAT_RIPOSTE_CD, DeleteLocalInt(oPC, LEGFEAT_RIPOSTE_VAR));

    // The parry roll: d20 + Parry RANKS against the attacker's attack bonus.
    // Ranks, not the modified skill, for the same reason the prerequisite asks
    // for ranks - at this level cap the modified number is mostly gear.
    int nParry = d20() + GetSkillRank(SKILL_PARRY, oPC, TRUE);
    int nAtk   = d20() + GetBaseAttackBonus(oDamager);
    if (nParry < nAtk) return;

    int nDamage = LegFeatDmg_WeaponDamage(oPC);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
                        EffectDamage(nDamage, LegFeatDmg_PhysicalType(oPC)),
                        oDamager);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
                        EffectVisualEffect(VFX_COM_BLOOD_CRT_RED), oDamager);
    SendMessageToPC(oPC, "Legendary Riposte: " + IntToString(nDamage)
                       + " damage to " + GetName(oDamager) + ".");
}
