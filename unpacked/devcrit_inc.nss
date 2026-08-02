// devcrit_inc.nss — shared helpers for the Devastating Critical rework.
//
// Roadmap: devcrit-roll. Devastating Critical stops being save-or-die and
// becomes flat bonus physical damage, typed to the weapon's base damage type
// and scaled by weapon size. Legendary Butcher stacks +5 more dice on top.
// The rule is SYMMETRIC — it applies to NPCs and players alike.
//
// Two mechanisms, because the engine uses two:
//   1. the bonus damage is added in the NWNX Damage ATTACK event
//      (devcrit_atk.nss), which can see iAttackResult == 10;
//   2. the instant kill is an EffectDeath, NOT damage, so the damage event
//      cannot suppress it. devcrit_eff.nss skips it from
//      NWNX_ON_EFFECT_APPLIED_BEFORE, discriminated by the short-lived flag
//      this file stamps on the victim.
//
// The attack handler runs on EVERY attack on the server. Keep everything here
// cheap and keep the callers' early-returns first.

// legfeat_ids_inc is where FEAT_LEGENDARY_BUTCHER's id comes from — it is
// GENERATED from bin/gen-legendary-feats.py, so the id here and the row in
// hak_2da/feat.2da cannot drift. Never hardcode the number.
#include "legfeat_ids_inc"
#include "nwnx_events"

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

// Bonus dice for this attack. nAttackResult is NWNX_Damage's iAttackResult
// (3 = critical hit, 10 = devastating critical). Returns 0 when nothing applies
// — the caller must treat 0 as "return immediately".
int DevCrit_BonusDice(object oAttacker, int nAttackResult);

// Die size (6/8/10) for oWeapon. OBJECT_INVALID — unarmed and creature attacks
// — is small.
int DevCrit_DieSize(object oWeapon);

// Total of nDice dice of nSize.
int DevCrit_Roll(int nDice, int nSize);

// Stamp the "refuse the next death effect" flag on oTarget, self-clearing.
void DevCrit_FlagNoKill(object oTarget);

// TRUE while the flag stamped by DevCrit_FlagNoKill is live.
int DevCrit_IsNoKill(object oTarget);

// Internal — the delayed clear. Only clears when no later devastating critical
// has re-stamped the flag, so two dev crits in the same window cannot leave the
// second one unprotected.
void DevCrit_ClearNoKill(object oTarget, int nToken);


int DevCrit_BonusDice(object oAttacker, int nAttackResult)
{
    int nDice = 0;
    if (nAttackResult == 10) nDice += DEVCRIT_DICE;

    // Butcher fires on an ordinary critical too, which is the whole point of
    // the feat: it is critical damage, not devastating-critical damage.
    if (GetHasFeat(FEAT_LEGENDARY_BUTCHER, oAttacker))
        nDice += DEVCRIT_DICE_BUTCH;

    return nDice;
}

int DevCrit_DieSize(object oWeapon)
{
    if (!GetIsObjectValid(oWeapon)) return DEVCRIT_DIE_SMALL;

    // NWScript has no GetWeaponSize — it only exists in baseitems.2da.
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

int DevCrit_Roll(int nDice, int nSize)
{
    int nTotal = 0;
    int i;
    for (i = 0; i < nDice; i++) nTotal += Random(nSize) + 1;
    return nTotal;
}

void DevCrit_FlagNoKill(object oTarget)
{
    int nToken = GetLocalInt(oTarget, DEVCRIT_VAR_TOKEN) + 1;
    SetLocalInt(oTarget, DEVCRIT_VAR_TOKEN, nToken);
    SetLocalInt(oTarget, DEVCRIT_VAR_NOKILL, TRUE);

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
    // A later devastating critical bumped the token — that one owns the flag
    // now and will clear it when its own window closes.
    if (GetLocalInt(oTarget, DEVCRIT_VAR_TOKEN) != nToken) return;

    DeleteLocalInt(oTarget, DEVCRIT_VAR_NOKILL);
    DeleteLocalInt(oTarget, DEVCRIT_VAR_TOKEN);
}
