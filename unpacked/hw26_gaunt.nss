// hw26_gaunt - Gravewatch Gauntlets: Smash (activated on a target), 5 per 90
// real minutes. Must be within arm's reach. 10d12 + 5x Strength modifier
// bludgeoning; doubled against undead, constructs, doors and placeables. A
// pumpkin of the Harvest of Shadows breaks outright.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    object oT = GetLocalObject(oPC, "hw_target");
    int nType = GetObjectType(oT);
    if (!GetIsObjectValid(oT) || oT == oPC
        || (nType != OBJECT_TYPE_CREATURE && nType != OBJECT_TYPE_PLACEABLE && nType != OBJECT_TYPE_DOOR))
    {
        SendMessageToPC(oPC, "Smash needs a creature, door or object to strike.");
        return;
    }
    if (GetDistanceBetween(oPC, oT) > 4.0)
    {
        SendMessageToPC(oPC, "Smash: get within arm's reach first.");
        return;
    }
    if (nType == OBJECT_TYPE_CREATURE && !GetIsEnemy(oT, oPC))
    {
        SendMessageToPC(oPC, "Smash is for enemies.");
        return;
    }
    if (!HW_TryUse(oPC, "smash", "Smash", 5)) return;

    AssignCommand(oPC, PlayAnimation(ANIMATION_FIREFORGET_TAUNT));
    string sTag = GetTag(oT);
    if (sTag == HW_TAG_CURSED || sTag == HW_TAG_BOSS || sTag == HW_TAG_TOWN)
    {
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectDamage(GetCurrentHitPoints(oT) + GetHardness(oT) + 10, DAMAGE_TYPE_BLUDGEONING), oT);
        return;
    }
    int nDmg = d12(10) + 5 * GetAbilityModifier(ABILITY_STRENGTH, oPC);
    int nRace = (nType == OBJECT_TYPE_CREATURE) ? GetRacialType(oT) : -1;
    if (nType != OBJECT_TYPE_CREATURE || nRace == RACIAL_TYPE_UNDEAD || nRace == RACIAL_TYPE_CONSTRUCT)
        nDmg *= 2;
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_COM_CHUNK_BONE_MEDIUM), oT);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(nDmg, DAMAGE_TYPE_BLUDGEONING), oT);
}
