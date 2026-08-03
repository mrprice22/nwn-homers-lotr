// devcrit_atk.nss - NWNX Damage ATTACK event handler.
//
// Roadmap: devcrit-roll. Adds the bonus physical damage that replaces the
// Devastating Critical save-or-die.
//
// The save-or-die itself is gone at the source: hak_2da/baseitems.2da has a
// blank EpicWeaponDevastatingCriticalFeat column, so the engine's own check
// (CNWSCreatureStats::GetEpicWeaponDevastatingCritical) can never succeed and
// no save is ever rolled. See bin/gen-devcrit-map.py - it is also what
// generates devcrit_map_inc.nss, the base item -> feat table that used to be
// that column and that this script now uses to decide who earns the dice.
//
// Consequence: iAttackResult 10 no longer happens. The bonus dice ride on an
// ORDINARY critical (result 3) for an attacker holding the Devastating
// Critical feat that matches the weapon in hand.
//
// Registered server-wide from onmoduleload.nss:
//     NWNX_Damage_SetAttackEventScript("devcrit_atk");
//
// OBJECT_SELF is the ATTACKER; the victim is data.oTarget.
//
// ###########################################################################
// # THIS RUNS ON EVERY ATTACK ON THE SERVER. A bug here is a bug in ALL      #
// # combat, not just in critical hits. The iAttackResult test below is the   #
// # first thing after fetching the event data and must stay that way - every #
// # non-critical attack has to leave through it. tests/check_devcrit.py      #
// # asserts the guard is still in place.                                     #
// ###########################################################################

#include "nwnx_damage"
#include "devcrit_inc"
#include "cbd_inc"
#include "legfeat_atk_inc"

void main()
{
    struct NWNX_Damage_AttackEventData data = NWNX_Damage_GetAttackEventData();

    // Combat Dummy (roadmap combat-dummy) counts attacks per round, so it needs
    // MISSES too and cannot sit behind the critical guard below. One
    // GetLocalInt on the target is the whole cost for every other attack on the
    // server; keep it that way. Everything else lives in cbd_inc.
    if (GetLocalInt(data.oTarget, CBD_VAR_IS_DUMMY)) CBD_TrackAttack(data);

    // Attacker-side legendary feats (Wrath, Quarry, Sundering, Reaping) fire on
    // ORDINARY hits, so like the dummy they cannot sit behind the critical
    // guard below. Same deal as the dummy too: one GetLocalInt on the attacker
    // for every other attack on the server, and the flag is only ever set on a
    // character who actually holds one of those feats (LegFeat_ArmHooks). The
    // hook does not touch `data` - see the header of legfeat_atk_inc.nss.
    if (GetLocalInt(OBJECT_SELF, LEGFEAT_ATK_VAR)) LegFeatAtk_OnAttack(data);

    // The hot path: everything that is not a critical leaves here.
    int nResult = data.iAttackResult;
    if (nResult != 3 && nResult != 10) return;

    object oAttacker = OBJECT_SELF;

    // Which weapon actually swung. Creature attacks (3-5) and unarmed (7-8)
    // have no weapon object and fall through to small dice, bludgeoning.
    // Needed before the dice, because since the engine's devastating critical
    // was disabled at source (see below) the WEAPON is what says whether this
    // critical earns the bonus dice.
    object oWeapon = OBJECT_INVALID;
    if (data.iWeaponAttackType == 1 || data.iWeaponAttackType == 6)
        oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oAttacker);
    else if (data.iWeaponAttackType == 2)
        oWeapon = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oAttacker);

    int nDice = DevCrit_BonusDice(oAttacker, nResult, oWeapon,
                                  data.iWeaponAttackType);

    // An ordinary critical by someone with neither Devastating Critical for
    // this weapon nor Legendary Butcher: nothing to do.
    if (nDice <= 0) return;

    // iAttackResult 10 should now be unreachable: hak_2da/baseitems.2da has a
    // blank EpicWeaponDevastatingCriticalFeat column, so the engine never
    // considers a devastating critical at all (bin/gen-devcrit-map.py). This
    // branch is the belt-and-braces for the one case that can still produce it
    // - a server or client running a stale hak - and is what devcrit_eff.nss
    // needs to refuse the kill.
    if (nResult == 10)
    {
        DevCrit_FlagNoKill(data.oTarget, oAttacker);
        if (DevCrit_IsDebug())
            DevCrit_Debug(data.oTarget, "devastating critical from " +
                          GetName(oAttacker) +
                          " - STALE HAK? no-kill window open");
    }

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

    // NWNX reports a damage type that was not dealt as -1, NOT as 0, so a bare
    // += on an unused type loses a point (a 15-point bonus on a weapon that
    // deals no slashing landed as 14 - visible in the UAT dump as
    // "base=96 slash=14" for a 15-point roll). DevCrit_AddDamage assigns when
    // the field is unset and adds when it is not.
    switch (nWeaponType)
    {
        case 1:  data.iPierce      = DevCrit_AddDamage(data.iPierce, nDamage);
                 break;
        case 3:
        case 4:  data.iSlash       = DevCrit_AddDamage(data.iSlash, nDamage);
                 break;  // 4 picks slashing
        default: data.iBludgeoning = DevCrit_AddDamage(data.iBludgeoning,
                                                       nDamage);
                 break;
    }

    NWNX_Damage_SetAttackEventData(data);
}
