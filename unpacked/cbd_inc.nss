// cbd_inc.nss — Combat Dummy: shared state machine.
//
// Roadmap: combat-dummy. A hostile, immobile, indestructible creature that
// measures what a character actually does in combat over a fixed 10 rounds:
//   * attacks per round (APR) — reported only, never stored;
//   * damage per round  (DPR) — reported AND written to the leaderboard.
//
// It exists because several feats change nothing on the character sheet
// (stock Flurry of Blows, the legendary monk extra attack), so the only way to
// tell whether they fire is to count real swings against a real target.
//
// --- how the two halves are wired -------------------------------------------
// DAMAGE (for DPR) comes from a PER-OBJECT NWNX Damage damage-event handler the
// dummy registers on ITSELF at spawn (cbd_spawn -> cbd_damage). Per-object, so
// it costs the rest of the server nothing. That handler ZEROES every damage
// field before returning it: the dummy's HP never moves, which is why Harm and
// Drown cannot kill it and why no healing loop is needed.
//
// ATTACKS (for APR) can only come from the NWNX Damage ATTACK event, because
// that is the only place a MISS is visible. That event script slot is global
// and belongs to devcrit_atk.nss, so devcrit_atk calls CBD_TrackAttack() behind
// a single GetLocalInt guard. Keep that guard cheap — it runs on every attack
// on the server.
//
// --- session state (all locals on the DUMMY) --------------------------------
//   CBD_IS_DUMMY  1 on a live dummy (the handlers' identity check)
//   CBD_ACTIVE    1 while a 10-round session is running
//   CBD_TOKEN     session serial; every delayed round tick carries the token it
//                 was scheduled with, so a cancelled session's pending ticks
//                 become no-ops instead of firing into the next session
//   CBD_OWNER     the PC being measured
//   CBD_ROUND     rounds completed so far
//   CBD_ATK_TOT / CBD_HIT_TOT / CBD_DMG_TOT   session totals
//   CBD_ATK_RND / CBD_DMG_RND                 this round, reset every tick
//   CBD_COOL      1 during the post-session cooldown (attacks are ignored)
//   CBD_SPAWN     the location cbd_death respawns at
//   CBD_IDLE      seconds since the owner last attacked or dealt damage; the
//                 watchdog abandons the session at CBD_IDLE_LIMIT

#include "nwnx_damage"
#include "cbd_db"

const int   CBD_ROUNDS     = 10;    // rounds in a session
const float CBD_ROUND_SECS = 6.0;   // one NWN combat round
const float CBD_COOL_SECS  = 12.0;  // grace after a session, so trailing swings
                                    // don't immediately start the next one
const float CBD_PETRIFY    = 10.0;  // intruder lock-out (same as _attackplaceable)
const float CBD_WATCH_SECS = 1.0;   // idle watchdog resolution
const int   CBD_IDLE_LIMIT = 5;     // seconds of no attack/damage = abandoned

const string CBD_VAR_IS_DUMMY = "CBD_IS_DUMMY";
const string CBD_VAR_ACTIVE   = "CBD_ACTIVE";
const string CBD_VAR_TOKEN    = "CBD_TOKEN";
const string CBD_VAR_OWNER    = "CBD_OWNER";
const string CBD_VAR_ROUND    = "CBD_ROUND";
const string CBD_VAR_ATK_TOT  = "CBD_ATK_TOT";
const string CBD_VAR_HIT_TOT  = "CBD_HIT_TOT";
const string CBD_VAR_DMG_TOT  = "CBD_DMG_TOT";
const string CBD_VAR_ATK_RND  = "CBD_ATK_RND";
const string CBD_VAR_DMG_RND  = "CBD_DMG_RND";
const string CBD_VAR_COOL     = "CBD_COOL";
const string CBD_VAR_SPAWN    = "CBD_SPAWN";
const string CBD_VAR_WARNED   = "CBD_WARNED";
const string CBD_VAR_IDLE     = "CBD_IDLE";

const string CBD_RESREF = "cbd_dummy";   // for the respawn in cbd_death

// ---------------------------------------------------------------------------
// Prototypes (CBD_RoundTick is delayed recursively, so it must be declared
// before it is used).

object CBD_OwnerPC(object oSrc);
void   CBD_Say(object oPC, string sMsg);
void   CBD_ClearState(object oDummy);
void   CBD_StartSession(object oDummy, object oPC);
void   CBD_RoundTick(object oDummy, int nToken);
void   CBD_EndSession(object oDummy);
void   CBD_CancelSession(object oDummy, string sWhy);
void   CBD_ClearCooldown(object oDummy, int nToken);
void   CBD_Reject(object oDummy, object oSrc);
void   CBD_TrackAttack(struct NWNX_Damage_AttackEventData data);
void   CBD_Respawn(location lLoc);
void   CBD_Watchdog(object oDummy, int nToken);
void   CBD_Touch(object oDummy);

// ---------------------------------------------------------------------------

// DelayCommand can only defer a void call, and CreateObject returns an object,
// so the respawn in cbd_death goes through this.
void CBD_Respawn(location lLoc)
{
    CreateObject(OBJECT_TYPE_CREATURE, CBD_RESREF, lLoc);
}

// The PC that owns oSrc: oSrc itself if it is a PC, else the top of its master
// chain (summons, familiars, henchmen, dominated creatures). OBJECT_INVALID if
// nothing player-controlled is behind it.
object CBD_OwnerPC(object oSrc)
{
    int i = 0;
    while (GetIsObjectValid(oSrc) && !GetIsPC(oSrc) && i < 5)
    {
        oSrc = GetMaster(oSrc);
        i++;
    }
    return GetIsPC(oSrc) ? oSrc : OBJECT_INVALID;
}

// Every report goes to BOTH the floating text (immediate, unmissable) and the
// chat log (scrollable, so a missed round can still be read afterwards).
void CBD_Say(object oPC, string sMsg)
{
    if (!GetIsObjectValid(oPC)) return;
    SendMessageToPC(oPC, sMsg);
    FloatingTextStringOnCreature(sMsg, oPC, FALSE);
}

// Any activity from the owner resets the idle clock. Called from both the
// attack and the damage handler.
void CBD_Touch(object oDummy)
{
    SetLocalInt(oDummy, CBD_VAR_IDLE, 0);
}

void CBD_ClearState(object oDummy)
{
    DeleteLocalInt(oDummy, CBD_VAR_IDLE);
    DeleteLocalInt(oDummy, CBD_VAR_ACTIVE);
    DeleteLocalObject(oDummy, CBD_VAR_OWNER);
    DeleteLocalInt(oDummy, CBD_VAR_ROUND);
    DeleteLocalInt(oDummy, CBD_VAR_ATK_TOT);
    DeleteLocalInt(oDummy, CBD_VAR_HIT_TOT);
    DeleteLocalInt(oDummy, CBD_VAR_DMG_TOT);
    DeleteLocalInt(oDummy, CBD_VAR_ATK_RND);
    DeleteLocalInt(oDummy, CBD_VAR_DMG_RND);
    DeleteLocalInt(oDummy, CBD_VAR_WARNED);
}

void CBD_StartSession(object oDummy, object oPC)
{
    // Bump the serial FIRST: any tick still pending from a previous session is
    // now stale and will drop out of CBD_RoundTick.
    int nToken = GetLocalInt(oDummy, CBD_VAR_TOKEN) + 1;
    SetLocalInt(oDummy, CBD_VAR_TOKEN, nToken);

    CBD_ClearState(oDummy);
    SetLocalInt(oDummy, CBD_VAR_ACTIVE, 1);
    SetLocalObject(oDummy, CBD_VAR_OWNER, oPC);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
                        EffectVisualEffect(VFX_FNF_LOS_HOLY_10), oDummy);

    CBD_Say(oPC, "Combat test started: " + IntToString(CBD_ROUNDS) +
                 " rounds. Keep attacking the dummy.");

    AssignCommand(oDummy,
        DelayCommand(CBD_ROUND_SECS, CBD_RoundTick(oDummy, nToken)));
    AssignCommand(oDummy,
        DelayCommand(CBD_WATCH_SECS, CBD_Watchdog(oDummy, nToken)));
}

// A trial only means anything if the tester keeps swinging: idle rounds would
// drag APR and DPR toward zero and then record that as a score. So the session
// is abandoned after CBD_IDLE_LIMIT seconds with no attack and no damage, and
// immediately if the owner leaves the area or dies. Nothing is recorded.
// Runs once a second, but only while a session is actually open.
void CBD_Watchdog(object oDummy, int nToken)
{
    if (!GetIsObjectValid(oDummy)) return;
    if (GetLocalInt(oDummy, CBD_VAR_TOKEN) != nToken) return;
    if (!GetLocalInt(oDummy, CBD_VAR_ACTIVE)) return;

    object oPC = GetLocalObject(oDummy, CBD_VAR_OWNER);
    if (!GetIsObjectValid(oPC) || GetIsDead(oPC))
    {
        CBD_CancelSession(oDummy, "");
        return;
    }
    if (GetArea(oPC) != GetArea(oDummy))
    {
        CBD_CancelSession(oDummy, "Combat test cancelled - you left the area. Nothing was recorded.");
        return;
    }

    int nIdle = GetLocalInt(oDummy, CBD_VAR_IDLE) + 1;
    SetLocalInt(oDummy, CBD_VAR_IDLE, nIdle);
    if (nIdle >= CBD_IDLE_LIMIT)
    {
        CBD_CancelSession(oDummy, "Combat test cancelled - you stopped attacking for " +
                                  IntToString(CBD_IDLE_LIMIT) + " seconds. Nothing was recorded.");
        return;
    }

    AssignCommand(oDummy,
        DelayCommand(CBD_WATCH_SECS, CBD_Watchdog(oDummy, nToken)));
}

void CBD_RoundTick(object oDummy, int nToken)
{
    // Stale tick from a cancelled or superseded session.
    if (!GetIsObjectValid(oDummy)) return;
    if (GetLocalInt(oDummy, CBD_VAR_TOKEN) != nToken) return;
    if (!GetLocalInt(oDummy, CBD_VAR_ACTIVE)) return;

    object oPC = GetLocalObject(oDummy, CBD_VAR_OWNER);
    if (!GetIsObjectValid(oPC) || GetIsDead(oPC))
    {
        CBD_CancelSession(oDummy, "");
        return;
    }

    int nRound = GetLocalInt(oDummy, CBD_VAR_ROUND) + 1;
    SetLocalInt(oDummy, CBD_VAR_ROUND, nRound);

    int nAtk = GetLocalInt(oDummy, CBD_VAR_ATK_RND);
    int nDmg = GetLocalInt(oDummy, CBD_VAR_DMG_RND);
    SetLocalInt(oDummy, CBD_VAR_ATK_RND, 0);
    SetLocalInt(oDummy, CBD_VAR_DMG_RND, 0);

    CBD_Say(oPC, "Round " + IntToString(nRound) + "/" +
                 IntToString(CBD_ROUNDS) + ": " + IntToString(nAtk) +
                 " attacks, " + IntToString(nDmg) + " damage.");

    if (nRound >= CBD_ROUNDS)
    {
        CBD_EndSession(oDummy);
        return;
    }

    AssignCommand(oDummy,
        DelayCommand(CBD_ROUND_SECS, CBD_RoundTick(oDummy, nToken)));
}

void CBD_EndSession(object oDummy)
{
    object oPC   = GetLocalObject(oDummy, CBD_VAR_OWNER);
    int nAtkTot  = GetLocalInt(oDummy, CBD_VAR_ATK_TOT);
    int nHitTot  = GetLocalInt(oDummy, CBD_VAR_HIT_TOT);
    int nDmgTot  = GetLocalInt(oDummy, CBD_VAR_DMG_TOT);

    float fApr = IntToFloat(nAtkTot) / IntToFloat(CBD_ROUNDS);
    float fDpr = IntToFloat(nDmgTot) / IntToFloat(CBD_ROUNDS);

    // Close the session before anything that can fail, so a DB problem can
    // never leave the dummy stuck "active".
    int nToken = GetLocalInt(oDummy, CBD_VAR_TOKEN) + 1;
    SetLocalInt(oDummy, CBD_VAR_TOKEN, nToken);
    CBD_ClearState(oDummy);
    SetLocalInt(oDummy, CBD_VAR_COOL, 1);
    AssignCommand(oDummy,
        DelayCommand(CBD_COOL_SECS, CBD_ClearCooldown(oDummy, nToken)));

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
                        EffectVisualEffect(VFX_FNF_TIME_STOP), oDummy);

    if (!GetIsObjectValid(oPC)) return;

    CBD_Say(oPC, "Combat test complete (" + IntToString(CBD_ROUNDS) +
                 " rounds).");
    CBD_Say(oPC, "  Attacks per round: " + FloatToString(fApr, 0, 2) +
                 "   (" + IntToString(nHitTot) + " hits / " +
                 IntToString(nAtkTot) + " attacks)");
    CBD_Say(oPC, "  Damage per round:  " + FloatToString(fDpr, 0, 1) +
                 "   (" + IntToString(nDmgTot) + " total)");

    // Nothing happened — don't pollute the leaderboard with idle sessions.
    if (nDmgTot <= 0) return;

    Cbd_Record(oPC, fDpr, nDmgTot, CBD_ROUNDS);
    CBD_Say(oPC, "  Recorded to the Hall of Champions.");
}

void CBD_CancelSession(object oDummy, string sWhy)
{
    object oPC = GetLocalObject(oDummy, CBD_VAR_OWNER);
    SetLocalInt(oDummy, CBD_VAR_TOKEN, GetLocalInt(oDummy, CBD_VAR_TOKEN) + 1);
    CBD_ClearState(oDummy);
    if (sWhy != "") CBD_Say(oPC, sWhy);
    else CBD_Say(oPC, "Combat test cancelled — nothing recorded.");
}

void CBD_ClearCooldown(object oDummy, int nToken)
{
    if (!GetIsObjectValid(oDummy)) return;
    if (GetLocalInt(oDummy, CBD_VAR_TOKEN) != nToken) return;
    DeleteLocalInt(oDummy, CBD_VAR_COOL);
}

// Somebody who is not the session owner touched an active dummy: freeze them
// for a moment and tell them why. Their damage is discarded by the caller.
void CBD_Reject(object oDummy, object oSrc)
{
    if (!GetIsObjectValid(oSrc)) return;

    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, EffectPetrify(), oSrc,
                        CBD_PETRIFY);

    object oPC = CBD_OwnerPC(oSrc);
    if (!GetIsObjectValid(oPC)) return;

    // One message per session per intruder — the handler fires on every swing.
    string sVar = "CBD_TOLD_" + ObjectToString(oDummy);
    if (GetLocalInt(oPC, sVar) == GetLocalInt(oDummy, CBD_VAR_TOKEN)) return;
    SetLocalInt(oPC, sVar, GetLocalInt(oDummy, CBD_VAR_TOKEN));

    object oOwner = GetLocalObject(oDummy, CBD_VAR_OWNER);
    CBD_Say(oPC, "This combat dummy is in use by " + GetName(oOwner) +
                 ". Wait for the test to finish — your damage is not counted.");
}

// Called from devcrit_atk.nss on every attack whose target is a dummy.
// OBJECT_SELF is the attacker; data.oTarget is the dummy.
//
// This is also one of the two places a session can START. It has to be: the
// attack event resolves BEFORE the damage event, so if only cbd_damage could
// open a session, the swing that opened it would never be counted and every
// APR reading would be one attack light in round 1.
void CBD_TrackAttack(struct NWNX_Damage_AttackEventData data)
{
    object oDummy = data.oTarget;
    if (GetLocalInt(oDummy, CBD_VAR_COOL)) return;

    object oPC = CBD_OwnerPC(OBJECT_SELF);

    if (!GetLocalInt(oDummy, CBD_VAR_ACTIVE))
    {
        if (!GetIsObjectValid(oPC)) return;
        CBD_StartSession(oDummy, oPC);
    }
    else if (oPC != GetLocalObject(oDummy, CBD_VAR_OWNER))
    {
        CBD_Reject(oDummy, OBJECT_SELF);
        return;
    }

    CBD_Touch(oDummy);
    SetLocalInt(oDummy, CBD_VAR_ATK_RND, GetLocalInt(oDummy, CBD_VAR_ATK_RND) + 1);
    SetLocalInt(oDummy, CBD_VAR_ATK_TOT, GetLocalInt(oDummy, CBD_VAR_ATK_TOT) + 1);

    // iAttackResult: 1 hit, 2 parried, 3 critical, 4 miss, 5 resisted,
    // 7 automatic hit, 8 concealed, 9 miss chance, 10 devastating critical.
    int nRes = data.iAttackResult;
    if (nRes == 1 || nRes == 3 || nRes == 7 || nRes == 10)
        SetLocalInt(oDummy, CBD_VAR_HIT_TOT,
                    GetLocalInt(oDummy, CBD_VAR_HIT_TOT) + 1);
}
