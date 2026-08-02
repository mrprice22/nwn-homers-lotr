// devcrit_atk.nss — NWNX Damage ATTACK event handler.
//
// Roadmap: devcrit-roll. Adds the bonus physical damage that replaces the
// Devastating Critical save-or-die, and stamps the flag devcrit_eff.nss uses to
// refuse the engine's instant kill.
//
// Registered server-wide from onmoduleload.nss:
//     NWNX_Damage_SetAttackEventScript("devcrit_atk");
//
// OBJECT_SELF is the ATTACKER; the victim is data.oTarget.
//
// ###########################################################################
// # THIS RUNS ON EVERY ATTACK ON THE SERVER. A bug here is a bug in ALL      #
// # combat, not just in critical hits. The iAttackResult test below is the   #
// # first thing after fetching the event data and must stay that way — every #
// # non-critical attack has to leave through it. tests/check_devcrit.py      #
// # asserts the guard is still in place.                                     #
// ###########################################################################

#include "nwnx_damage"
#include "devcrit_inc"
#include "cbd_inc"

void main()
{
    struct NWNX_Damage_AttackEventData data = NWNX_Damage_GetAttackEventData();

    // Combat Dummy (roadmap combat-dummy) counts attacks per round, so it needs
    // MISSES too and cannot sit behind the critical guard below. One
    // GetLocalInt on the target is the whole cost for every other attack on the
    // server; keep it that way. Everything else lives in cbd_inc.
    if (GetLocalInt(data.oTarget, CBD_VAR_IS_DUMMY)) CBD_TrackAttack(data);

    // The hot path: everything that is not a critical leaves here.
    int nResult = data.iAttackResult;
    if (nResult != 3 && nResult != 10) return;

    object oAttacker = OBJECT_SELF;
    int nDice = DevCrit_BonusDice(oAttacker, nResult);

    // An ordinary critical by someone without Legendary Butcher: nothing to do.
    if (nDice <= 0) return;

    // Refuse the engine's instant kill. Done before the damage so that a
    // devastating critical still suppresses the death even if something below
    // adds nothing.
    if (nResult == 10) DevCrit_FlagNoKill(data.oTarget);

    // Which weapon actually swung. Creature attacks (3-5) and unarmed (7-8)
    // have no weapon object and fall through to small dice, bludgeoning.
    object oWeapon = OBJECT_INVALID;
    if (data.iWeaponAttackType == 1 || data.iWeaponAttackType == 6)
        oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oAttacker);
    else if (data.iWeaponAttackType == 2)
        oWeapon = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oAttacker);

    int nDamage = DevCrit_Roll(nDice, DevCrit_DieSize(oWeapon));
    if (nDamage <= 0) return;

    // Typed to the weapon's own damage type, from baseitems.2da WeaponType:
    // 1 = piercing, 2 = bludgeoning, 3 = slashing, 4 = slashing/piercing.
    // No weapon (fists, claws, bites) is bludgeoning.
    int nWeaponType = 2;
    if (GetIsObjectValid(oWeapon))
    {
        int n = StringToInt(Get2DAString("baseitems", "WeaponType",
                                         GetBaseItemType(oWeapon)));
        if (n >= 1 && n <= 4) nWeaponType = n;
    }

    switch (nWeaponType)
    {
        case 1:  data.iPierce      += nDamage; break;
        case 3:
        case 4:  data.iSlash       += nDamage; break;  // 4 picks slashing
        default: data.iBludgeoning += nDamage; break;
    }

    NWNX_Damage_SetAttackEventData(data);
}
