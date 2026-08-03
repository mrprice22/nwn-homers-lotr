// devcrit_inc.nss - shared helpers for the Devastating Critical rework.
//
// Roadmap: devcrit-roll. Devastating Critical stops being save-or-die and
// becomes flat bonus physical damage, typed to the weapon's base damage type
// and scaled by weapon size. Legendary Butcher stacks +5 more dice on top.
// The rule is SYMMETRIC - it applies to NPCs and players alike.
//
// Three parts, in the order they matter:
//   1. the save-or-die is disabled AT SOURCE: hak_2da/baseitems.2da carries a
//      blank EpicWeaponDevastatingCriticalFeat column, so the engine's own
//      check never succeeds and no save is rolled. bin/gen-devcrit-map.py owns
//      that edit and generates devcrit_map_inc.nss from the column it blanks;
//   2. the bonus damage is added in the NWNX Damage ATTACK event
//      (devcrit_atk.nss), on an ORDINARY critical, to an attacker holding the
//      Devastating Critical feat for the weapon in hand;
//   3. devcrit_eff.nss is the leftover safety net for a stale hak, where the
//      engine still resolves its own devastating critical: it refuses the
//      resulting death effect, discriminated by the short-lived flag this file
//      stamps on the victim. UAT showed it does NOT catch the engine's kill on
//      its own, which is exactly why part 1 exists - do not rely on it.
//
// The attack handler runs on EVERY attack on the server. Keep everything here
// cheap and keep the callers' early-returns first.

// legfeat_ids_inc is where FEAT_LEGENDARY_BUTCHER's id comes from - it is
// GENERATED from bin/gen-legendary-feats.py, so the id here and the row in
// hak_2da/feat.2da cannot drift. Never hardcode the number.
#include "legfeat_ids_inc"
// devcrit_map_inc is GENERATED (bin/gen-devcrit-map.py) from the
// EpicWeaponDevastatingCriticalFeat column this rework blanks in
// hak_2da/baseitems.2da. Same rule as legfeat_ids_inc: never hardcode the ids.
#include "devcrit_map_inc"
#include "nwnx_events"
#include "color"        // COLOR_RED for the diagnostic lines

// ---------------------------------------------------------------------------
// The numbers. These are the published design (roadmap.yaml, devcrit-roll) and
// tests/check_devcrit.py asserts they still match it, so the code and the
// public roadmap card cannot drift apart. Do not tune them here alone.
// ---------------------------------------------------------------------------
const int DEVCRIT_DICE      = 3;   // Devastating Critical, on iAttackResult 10
const int DEVCRIT_DICE_BUTCH = 5;  // Legendary Butcher, on any critical, stacks

// Die size by baseitems.2da WeaponSize: 1-2 small, 3 medium, 4 large.
const int DEVCRIT_DIE_SMALL  = 6;
const int DEVCRIT_DIE_MEDIUM = 8;
const int DEVCRIT_DIE_LARGE  = 10;

// NWNX_ON_EFFECT_APPLIED_*'s "TYPE" is the INTERNAL NWNXLib enum and does NOT
// match the NWScript EFFECT_TYPE_* constants (see nwnx_events.nss, "Effect
// Applied/Removed Events"). This value is EffectTrueType::Death from
// NWNXLib/API/Constants/Effect.hpp in nwnxee/unified. Verified against the
// header, not inferred: guessing it would either do nothing or silently
// suppress an unrelated class of effect for the whole server.
const int DEVCRIT_EFFTYPE_DEATH = 19;

// How long the "this death is a devastating critical, refuse it" flag lives.
// The EffectDeath lands in the same combat resolution as the attack, so this is
// generous; it exists only so a flag can never be left set forever.
const float DEVCRIT_FLAG_WINDOW = 2.0;

const string DEVCRIT_VAR_NOKILL = "DEVCRIT_NOKILL";
const string DEVCRIT_VAR_TOKEN  = "DEVCRIT_NOKILL_TOK";

// The attacker whose devastating critical opened the current window, kept on
// the victim so the diagnostics below have someone to report to.
const string DEVCRIT_VAR_SRC    = "DEVCRIT_SRC";

// Diagnostic mode, a local on the MODULE:
//     SetLocalInt(GetModule(), "DEVCRIT_DEBUG", 1);
// While it is on, every effect that lands on a victim inside a devastating
// critical's window is reported with its raw internal TYPE. That is the only
// way to see whether the engine's kill arrives as an applied effect at all,
// and if it does, under which enum value - the two failure modes that make
// this whole rework silently do nothing. OFF by default; behaviour with it off
// is exactly as before.
const string DEVCRIT_VAR_DEBUG  = "DEVCRIT_DEBUG";

// TRUE if oAttacker holds the Devastating Critical feat for what is in hand.
// oWeapon may be OBJECT_INVALID, in which case nWeaponAttackType decides
// between the unarmed and the creature-weapon feat.
int DevCrit_HasDevCrit(object oAttacker, object oWeapon, int nWeaponAttackType);

// Bonus dice for this attack. nAttackResult is NWNX_Damage's iAttackResult
// (3 = critical hit; 10 = devastating critical, which the engine no longer
// produces - see the header of devcrit_atk.nss). Returns 0 when nothing applies
// - the caller must treat 0 as "return immediately".
int DevCrit_BonusDice(object oAttacker, int nAttackResult, object oWeapon,
                      int nWeaponAttackType);

// Die size (6/8/10) for oWeapon. OBJECT_INVALID - unarmed and creature attacks
// - is small.
int DevCrit_DieSize(object oWeapon);

// Total of nDice dice of nSize.
int DevCrit_Roll(int nDice, int nSize);

// Add nDamage to one of NWNX's per-type damage fields. NWNX uses -1 for "this
// type was not dealt", so a bare += on an unused type silently loses a point.
int DevCrit_AddDamage(int nField, int nDamage);

// Stamp the "refuse the next death effect" flag on oTarget, self-clearing.
// oAttacker is remembered only so the diagnostics have a recipient.
void DevCrit_FlagNoKill(object oTarget, object oAttacker = OBJECT_INVALID);

// TRUE while diagnostic mode is on (DEVCRIT_VAR_DEBUG on the module).
int DevCrit_IsDebug();

// Diagnostic line about oTarget: to the attacker that opened the window when
// that is a player, otherwise to every DM online.
void DevCrit_Debug(object oTarget, string sMsg);

// TRUE while the flag stamped by DevCrit_FlagNoKill is live.
int DevCrit_IsNoKill(object oTarget);

// Internal - the delayed clear. Only clears when no later devastating critical
// has re-stamped the flag, so two dev crits in the same window cannot leave the
// second one unprotected.
void DevCrit_ClearNoKill(object oTarget, int nToken);


int DevCrit_HasDevCrit(object oAttacker, object oWeapon, int nWeaponAttackType)
{
    int nFeat;

    if (GetIsObjectValid(oWeapon))
        nFeat = DevCrit_WeaponFeat(GetBaseItemType(oWeapon));
    else if (nWeaponAttackType >= 3 && nWeaponAttackType <= 5)
        nFeat = FEAT_EPIC_DEVASTATING_CRITICAL_CREATURE;   // claws, bites, gores
    else
        nFeat = FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED;

    // -1: a base item that never had a devastating critical feat at all.
    if (nFeat < 0) return FALSE;

    return GetHasFeat(nFeat, oAttacker);
}

int DevCrit_BonusDice(object oAttacker, int nAttackResult, object oWeapon,
                      int nWeaponAttackType)
{
    int nDice = 0;

    // Result 10 is the stale-hak case (the engine still ran its own check and
    // won); the feat test is the live one. Either earns the same dice, and
    // they do NOT stack with each other.
    if (nAttackResult == 10 ||
        DevCrit_HasDevCrit(oAttacker, oWeapon, nWeaponAttackType))
        nDice += DEVCRIT_DICE;

    // Butcher fires on an ordinary critical too, which is the whole point of
    // the feat: it is critical damage, not devastating-critical damage.
    if (GetHasFeat(FEAT_LEGENDARY_BUTCHER, oAttacker))
        nDice += DEVCRIT_DICE_BUTCH;

    return nDice;
}

int DevCrit_DieSize(object oWeapon)
{
    if (!GetIsObjectValid(oWeapon)) return DEVCRIT_DIE_SMALL;

    // NWScript has no GetWeaponSize - it only exists in baseitems.2da.
    int nSize = StringToInt(Get2DAString("baseitems", "WeaponSize",
                                         GetBaseItemType(oWeapon)));
    switch (nSize)
    {
        case 4:  return DEVCRIT_DIE_LARGE;
        case 3:  return DEVCRIT_DIE_MEDIUM;
    }
    // 1, 2, and anything unset ("****" parses to 0) are small.
    return DEVCRIT_DIE_SMALL;
}

int DevCrit_AddDamage(int nField, int nDamage)
{
    return (nField > 0) ? nField + nDamage : nDamage;
}

int DevCrit_Roll(int nDice, int nSize)
{
    int nTotal = 0;
    int i;
    for (i = 0; i < nDice; i++) nTotal += Random(nSize) + 1;
    return nTotal;
}

int DevCrit_IsDebug()
{
    return GetLocalInt(GetModule(), DEVCRIT_VAR_DEBUG);
}

void DevCrit_Debug(object oTarget, string sMsg)
{
    // Bright red, like the Combat Dummy's dump: a diagnostic must not read as
    // ordinary feedback.
    string sLine = COLOR_RED + "[DEVCRIT] " + GetName(oTarget) + ": " + sMsg +
                   COLOR_END;

    object oSrc = GetLocalObject(oTarget, DEVCRIT_VAR_SRC);
    if (GetIsPC(oSrc)) SendMessageToPC(oSrc, sLine);
    else SendMessageToAllDMs(sLine);
}

void DevCrit_FlagNoKill(object oTarget, object oAttacker = OBJECT_INVALID)
{
    int nToken = GetLocalInt(oTarget, DEVCRIT_VAR_TOKEN) + 1;
    SetLocalInt(oTarget, DEVCRIT_VAR_TOKEN, nToken);
    SetLocalInt(oTarget, DEVCRIT_VAR_NOKILL, TRUE);
    SetLocalObject(oTarget, DEVCRIT_VAR_SRC, oAttacker);

    // Assigned to the module, not to the attacker: a delayed command on a
    // creature is cancelled when that creature is destroyed, which would strand
    // the flag on the victim forever.
    AssignCommand(GetModule(),
        DelayCommand(DEVCRIT_FLAG_WINDOW, DevCrit_ClearNoKill(oTarget, nToken)));
}

int DevCrit_IsNoKill(object oTarget)
{
    return GetLocalInt(oTarget, DEVCRIT_VAR_NOKILL);
}

void DevCrit_ClearNoKill(object oTarget, int nToken)
{
    // A later devastating critical bumped the token - that one owns the flag
    // now and will clear it when its own window closes.
    if (GetLocalInt(oTarget, DEVCRIT_VAR_TOKEN) != nToken) return;

    DeleteLocalInt(oTarget, DEVCRIT_VAR_NOKILL);
    DeleteLocalInt(oTarget, DEVCRIT_VAR_TOKEN);
    DeleteLocalObject(oTarget, DEVCRIT_VAR_SRC);
}
