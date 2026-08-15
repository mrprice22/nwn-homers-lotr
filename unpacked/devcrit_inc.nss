// devcrit_inc.nss - shared helpers for the Devastating Critical rework.
//
// Roadmap: devcrit-roll. Devastating Critical stops being save-or-die and
// becomes flat bonus physical damage, typed to the weapon's base damage type
// and scaled by weapon size. Legendary Butcher stacks +5 more dice on top.
// The rule is SYMMETRIC - it applies to NPCs and players alike.
//
// Three parts, in the order they matter:
//   1. the save-or-die is disabled AT SOURCE, TWICE, because the engine has two
//      ways of deciding whether an attacker has Devastating Critical:
//      a) an attack made with an ITEM looks the feat up in the attacker's
//         weapon's baseitems.2da row. hak_2da/baseitems.2da carries a blank
//         EpicWeaponDevastatingCriticalFeat column, so that lookup can never
//         succeed. bin/gen-devcrit-map.py owns that edit and generates
//         devcrit_map_inc.nss from the column it blanks;
//      b) an UNARMED or CREATURE-WEAPON attack does not go through that column
//         at all - the engine reaches for FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED
//         / _CREATURE itself, and no 2DA edit can reach it. So those two feats
//         are TAKEN OFF the creature instead (DevCrit_ArmNoDevCrit below), after
//         recording that it had them. Roadmap: devcrit-unarmed-save-or-die -
//         this is the half devcrit-roll missed, and it is why a monk on season 2
//         was still one-shotting things weeks after the "fix";
//   2. the bonus damage is added in the NWNX Damage ATTACK event
//      (devcrit_atk.nss), on an ORDINARY critical, to an attacker holding the
//      Devastating Critical feat for the weapon in hand - or, for unarmed and
//      creature attacks, to one that held it before part 1b stripped it;
//   3. there is no third part any more. devcrit_eff.nss - an
//      NWNX_ON_EFFECT_APPLIED_BEFORE subscriber that tried to refuse the
//      engine's death effect - was deleted: UAT proved it never caught the kill,
//      and being a per-effect global hook it was collateral damage in every
//      TOO MANY INSTRUCTIONS burst on the server. The no-kill flag it read is
//      kept below, because devcrit_atk still uses it to mark a victim for the
//      diagnostics when an engine devastating critical somehow gets through.
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
// NWNX_Creature_RemoveFeat is what takes the unarmed/creature devastating
// critical feats off a creature (NWNX_CREATURE_SKIP=n in server.env).
#include "nwnx_creature"
// Admin_CanAdmin - who gets told when the alarm below fires. There is no DM
// console on this server, so "tell the DMs" is not a delivery mechanism.
#include "admin_db"
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

// The snapshot left behind when DevCrit_ArmNoDevCrit strips a feat: "this
// creature HAD Devastating Critical (Unarmed / Creature) before we took it
// away". It is the permanent record of an entitlement, so it is a plain local
// with no window and it is never cleared - re-arming is idempotent because the
// local being set already means the feat is gone.
//
// legfeat_ids_inc.nss (GENERATED, and it has no includes) repeats these two
// names as string literals in LegFeat_HasAnyDevCrit, so that stripping the feat
// cannot cost a monk the Legendary Butcher prerequisite. tests/check_devcrit.py
// asserts the two spellings still match.
const string DEVCRIT_VAR_HAD_UNARMED  = "DEVCRIT_HAD_UNARMED";
const string DEVCRIT_VAR_HAD_CREATURE = "DEVCRIT_HAD_CREATURE";

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
// between the unarmed and the creature-weapon feat - and those two are read
// from the snapshot as well as from the feat, because DevCrit_ArmNoDevCrit has
// usually taken the feat away by then.
int DevCrit_HasDevCrit(object oAttacker, object oWeapon, int nWeaponAttackType);

// Take FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED / _CREATURE off oCreature and
// remember that it had them (DEVCRIT_VAR_HAD_*). This is what actually stops
// the save-or-die on an unarmed or creature-weapon attack: those two are the
// only devastating criticals the engine resolves WITHOUT reading the (blank)
// baseitems.2da column, so a blank table cannot reach them and possession of
// the feat is the only thing left to take away.
//
// Idempotent and cheap - two GetHasFeat calls once the strip has happened - so
// it is safe on every login, every level-up (a player can re-pick a feat that
// has been removed) and every spawn.
//
// The creature keeps the benefit: DevCrit_HasDevCrit reads the snapshot, so the
// replacement dice land exactly as before, and LegFeat_HasAnyDevCrit reads it
// too so the Legendary Butcher prerequisite still holds.
void DevCrit_ArmNoDevCrit(object oCreature);

// TRUE if oCreature held Devastating Critical (Unarmed) / (Creature) before
// DevCrit_ArmNoDevCrit took it, or still holds it because it has not been
// armed yet.
int DevCrit_HadUnarmed(object oCreature);
int DevCrit_HadCreature(object oCreature);

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

// The alarm on the branch that must never run: the engine resolved a
// devastating critical of its own (iAttackResult 10). Writes ONE server-log
// line - unconditionally, not behind the debug flag - carrying everything
// needed to say which lookup leaked: the attack type, the weapon (or
// "unarmed"), its base item row, and which of feats 0 / 506 / 532 the attacker
// holds. Also tells any admin who happens to be online.
void DevCrit_AlarmEngineCrit(object oAttacker, object oTarget, object oWeapon,
                             int nWeaponAttackType);

// Internal - the delayed clear. Only clears when no later devastating critical
// has re-stamped the flag, so two dev crits in the same window cannot leave the
// second one unprotected.
void DevCrit_ClearNoKill(object oTarget, int nToken);


int DevCrit_HadUnarmed(object oCreature)
{
    return GetLocalInt(oCreature, DEVCRIT_VAR_HAD_UNARMED)
        || GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED, oCreature);
}

int DevCrit_HadCreature(object oCreature)
{
    return GetLocalInt(oCreature, DEVCRIT_VAR_HAD_CREATURE)
        || GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_CREATURE, oCreature);
}

void DevCrit_ArmNoDevCrit(object oCreature)
{
    if (GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED, oCreature))
    {
        SetLocalInt(oCreature, DEVCRIT_VAR_HAD_UNARMED, TRUE);
        NWNX_Creature_RemoveFeat(oCreature,
                                 FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED);
    }

    if (GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_CREATURE, oCreature))
    {
        SetLocalInt(oCreature, DEVCRIT_VAR_HAD_CREATURE, TRUE);
        NWNX_Creature_RemoveFeat(oCreature,
                                 FEAT_EPIC_DEVASTATING_CRITICAL_CREATURE);
    }
}

int DevCrit_HasDevCrit(object oAttacker, object oWeapon, int nWeaponAttackType)
{
    int nFeat;

    if (GetIsObjectValid(oWeapon))
    {
        nFeat = DevCrit_WeaponFeat(GetBaseItemType(oWeapon));

        // -1: a base item that never had a devastating critical feat at all.
        if (nFeat < 0) return FALSE;

        return GetHasFeat(nFeat, oAttacker);
    }

    // No weapon object: claws/bites/gores (3-5), or fists. These are the two
    // the engine resolves on its own, so the feat has been stripped and the
    // snapshot is the entitlement - see DevCrit_ArmNoDevCrit.
    if (nWeaponAttackType >= 3 && nWeaponAttackType <= 5)
        return DevCrit_HadCreature(oAttacker);

    return DevCrit_HadUnarmed(oAttacker);
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

void DevCrit_AlarmEngineCrit(object oAttacker, object oTarget, object oWeapon,
                             int nWeaponAttackType)
{
    string sWeapon = "unarmed";
    if (GetIsObjectValid(oWeapon))
        sWeapon = GetResRef(oWeapon) + " (baseitem " +
                  IntToString(GetBaseItemType(oWeapon)) + ")";

    string sFeats =
        "alertness(0)=" +
        IntToString(GetHasFeat(FEAT_ALERTNESS, oAttacker)) +
        " unarmed(506)=" +
        IntToString(GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED,
                               oAttacker)) +
        " creature(532)=" +
        IntToString(GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_CREATURE,
                               oAttacker)) +
        " snapshot=" +
        IntToString(GetLocalInt(oAttacker, DEVCRIT_VAR_HAD_UNARMED)) + "/" +
        IntToString(GetLocalInt(oAttacker, DEVCRIT_VAR_HAD_CREATURE));

    string sLine = "[DEVCRIT ALARM] engine devastating critical (iAttackResult "
        + "10) - attacker '" + GetName(oAttacker) + "' vs '" +
        GetName(oTarget) + "', weaponAttackType " +
        IntToString(nWeaponAttackType) + ", weapon " + sWeapon + ", " + sFeats;

    // The server log is the record: this can fire on a live realm days before
    // anyone reads it, and the line is the whole diagnosis.
    WriteTimestampedLogEntry(sLine);

    // And anyone who can act on it, right now. There is no DM console here, so
    // "tell the DMs" would tell nobody.
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        if (Admin_CanAdmin(oPC))
            SendMessageToPC(oPC, COLOR_RED + sLine + COLOR_END);
        oPC = GetNextPC();
    }
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
