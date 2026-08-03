// cbd_inc.nss - Combat Dummy: shared state machine.
//
// Roadmap: combat-dummy. A hostile, immobile, indestructible creature that
// measures what a character actually does in combat over a fixed 10 rounds:
//   * attacks per round (APR) - reported only, never stored;
//   * damage per round  (DPR) - reported AND written to the leaderboard.
//
// It exists because several feats change nothing on the character sheet
// (stock Flurry of Blows, the legendary monk extra attack), so the only way to
// tell whether they fire is to count real swings against a real target.
//
// --- how the two halves are wired -------------------------------------------
// DAMAGE (for DPR) comes from a PER-OBJECT NWNX Damage damage-event handler the
// dummy registers on ITSELF at spawn (cbd_spawn -> cbd_damage). Per-object, so
// it costs the rest of the server nothing. The damage is allowed to LAND - so
// the combat log shows the real numbers, resistances and damage reduction - and
// the handler heals the dummy back to full on the next pulse (CBD_Restore).
// Death immunity and the OnDeath respawn sit behind that.
//
// ATTACKS (for APR) can only come from the NWNX Damage ATTACK event, because
// that is the only place a MISS is visible. That event script slot is global
// and belongs to devcrit_atk.nss, so devcrit_atk calls CBD_TrackAttack() behind
// a single GetLocalInt guard. Keep that guard cheap - it runs on every attack
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
#include "nwnx_object"   // SetCurrentHitPoints, for the heal-back in CBD_Restore
#include "cbd_db"
#include "admin_db"   // Admin_CanAdmin, for the admin auto-diagnostic
#include "color"

const int   CBD_ROUNDS     = 10;    // rounds in a session
const float CBD_ROUND_SECS = 6.0;   // one NWN combat round
const float CBD_COOL_SECS  = 12.0;  // grace after a session, so trailing swings
                                    // don't immediately start the next one
const float CBD_PETRIFY    = 10.0;  // intruder lock-out (same as _attackplaceable)
const float CBD_WATCH_SECS = 1.0;   // idle watchdog resolution
const int   CBD_IDLE_LIMIT = 5;     // seconds of no attack/damage = abandoned
const float CBD_DESTRUCT   = 1.5;   // pause after the final report before the
                                    // dummy self-destructs, so the spoken
                                    // summary lines are not cut off by death

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

// The attacker from the most recent attack event. NWNX's damage event does not
// reliably identify the damager for weapon damage, so this is what the damage
// handler attributes a hit to when data.oDamager resolves to nobody.
const string CBD_VAR_LAST_SRC = "CBD_LAST_SRC";

// Diagnostic mode: every attack and every damage packet is echoed to the tester
// with its raw event fields and the branch it took, so a "the numbers look
// wrong" report can be reconciled against the combat log packet by packet.
//
// Three ways it turns on, all behind a single GetLocalInt on the hot path:
//   * CBD_DEBUG on the dummy      - set by hand from the toolset;
//   * CBD_DEBUG on the module     - what dbg_combat flips server-wide;
//   * the tester is an ADMIN      - resolved ONCE per session in
//                                   CBD_StartSession (one admindb SELECT) and
//                                   cached on the dummy, so an admin never has
//                                   to reach for a DM console to get the dump.
//
// This is temporary UAT instrumentation (roadmap combat-dummy). When the
// measurement is settled, the admin auto-enable is the first thing to remove.
const string CBD_VAR_DEBUG    = "CBD_DEBUG";
const string CBD_VAR_DEBUG_ADMIN = "CBD_DEBUG_ADMIN";

// Diagnostic lines are bright red so they are distinguishable at a glance from
// the tool's own yellow output and from the engine's combat log.
const string CBD_DEBUG_COLOR = COLOR_RED;

const string CBD_RESREF = "cbd_dummy";   // for the respawn in cbd_death

// ---------------------------------------------------------------------------
// Prototypes (CBD_RoundTick is delayed recursively, so it must be declared
// before it is used).

object CBD_OwnerPC(object oSrc);
void   CBD_Say(object oPC, string sMsg);
void   CBD_Notice(object oPC, string sMsg);
void   CBD_Report(object oDummy, object oPC, string sMsg);
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
void   CBD_SelfDestruct(object oDummy, object oPC, int nToken);
int    CBD_Amt(int nValue);
object CBD_ResolveSrc(object oDummy, object oDamager);
void   CBD_ScheduleRestore(object oDummy);
void   CBD_Restore(object oDummy);
int    CBD_IsDebug(object oDummy);
string CBD_DbgField(string sName, int nVal);
void   CBD_Debug(object oDummy, object oPC, string sMsg);

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

// Every report goes out three ways, because the point of the tool is that the
// numbers survive long enough to be read:
//   * floating text over the tester  - immediate, but gone in seconds;
//   * SendMessageToPC                - the server channel, tagged and coloured
//                                      so it can be picked out of combat spam;
//   * the dummy SPEAKS the same line - the Talk channel, which is the copy that
//                                      is definitely still in the log to scroll
//                                      back to. The first UAT lost every line
//                                      when the float faded, so the spoken copy
//                                      is deliberate belt-and-braces, not an
//                                      accident.
// A one-off notice: the chat line only, no floating text. FloatingTextString-
// OnCreature ALSO echoes into the chat log, so a CBD_Say notice reads as the
// same sentence printed twice - which is what it looked like when the dummy
// said it was resetting. The round reports keep CBD_Say (and CBD_Report): there
// the repetition is deliberate, because each copy lands in a different place
// and outlives the others.
void CBD_Notice(object oPC, string sMsg)
{
    if (!GetIsObjectValid(oPC)) return;
    SendMessageToPC(oPC, COLOR_YELLOW + "[Combat Dummy] " + sMsg + COLOR_END);
}

void CBD_Say(object oPC, string sMsg)
{
    if (!GetIsObjectValid(oPC)) return;
    SendMessageToPC(oPC, COLOR_YELLOW + "[Combat Dummy] " + sMsg + COLOR_END);
    FloatingTextStringOnCreature(sMsg, oPC, FALSE);
}

// As CBD_Say, plus the dummy says it out loud so it lands in the Talk channel.
// Used for the lines a tester needs to be able to re-read: the round-by-round
// figures and the final averages.
void CBD_Report(object oDummy, object oPC, string sMsg)
{
    CBD_Say(oPC, sMsg);
    AssignCommand(oDummy, SpeakString(sMsg, TALKVOLUME_TALK));
}

// Who to credit a damage packet to. The damage event's own oDamager is the
// first choice, but for weapon damage it frequently resolves to nothing at all
// - which for a whole UAT set meant every hit fell into the "not the owner"
// branch and was discarded, giving "6 attacks, 0 damage" rounds and a DPR made
// of the few packets that happened to carry a source. The fallback is the
// attacker the attack event just stashed; the attack and its damage resolve in
// the same combat step, so it is the same swing.
object CBD_ResolveSrc(object oDummy, object oDamager)
{
    if (GetIsObjectValid(CBD_OwnerPC(oDamager))) return oDamager;

    object oLast = GetLocalObject(oDummy, CBD_VAR_LAST_SRC);
    if (GetIsObjectValid(oLast)) return oLast;

    return oDamager;
}

// Indestructibility, the visible way: the hit lands (so the combat log shows
// the damage, the resistances and any reduction), and this puts the HP back on
// the next pulse. DelayCommand(0.0) is deliberate - the damage has not been
// applied yet while this event script is running, so restoring now would be
// undone by the very hit being reported.
void CBD_ScheduleRestore(object oDummy)
{
    // On the module: a delayed command on the dummy is discarded if the dummy
    // is destroyed, and this is the one that has to survive the edge cases.
    AssignCommand(GetModule(), DelayCommand(0.0, CBD_Restore(oDummy)));
}

void CBD_Restore(object oDummy)
{
    if (!GetIsObjectValid(oDummy)) return;
    if (!GetLocalInt(oDummy, CBD_VAR_IS_DUMMY)) return;

    // Never undo the end-of-set self-destruct, and never haul a corpse back up.
    if (GetIsDead(oDummy)) return;

    int nMax = GetMaxHitPoints(oDummy);
    if (GetCurrentHitPoints(oDummy) >= nMax) return;

    NWNX_Object_SetCurrentHitPoints(oDummy, nMax);
}

// One damage field's contribution. NWNX reports a damage type that was NOT
// dealt as -1, not as 0 - so a plain sum of the 32 fields is the real damage
// MINUS the number of unused types. That is what made a 33-point greatsword hit
// measure as 2 and a 28-point hit as -3 ("packet carried no damage"), and it is
// why every damage field must go through here. Verified from the live dump:
// base=33 with 31 fields at -1 reported total=2.
int CBD_Amt(int nValue)
{
    return (nValue > 0) ? nValue : 0;
}

// ---- diagnostics (CBD_DEBUG) ----------------------------------------------

// On when the flag is set on this dummy specifically, or module-wide (which is
// what the dbg_combat admin script flips, so no toolset trip is needed).
int CBD_IsDebug(object oDummy)
{
    if (GetLocalInt(oDummy, CBD_VAR_DEBUG)) return TRUE;
    if (GetLocalInt(oDummy, CBD_VAR_DEBUG_ADMIN)) return TRUE;
    return GetLocalInt(GetModule(), CBD_VAR_DEBUG);
}

// " name=N" for a non-zero field, "" otherwise - so a dump lists only the
// damage types that actually arrived.
string CBD_DbgField(string sName, int nVal)
{
    // <= 0 rather than == 0: unused types come through as -1 (see CBD_Amt).
    if (nVal <= 0) return "";
    return " " + sName + "=" + IntToString(nVal);
}

// Diagnostic line: server channel only (no float, no SpeakString) so it cannot
// be confused with the tool's real output, and it is prefixed so it can be
// grepped out of a client log.
void CBD_Debug(object oDummy, object oPC, string sMsg)
{
    if (!GetIsObjectValid(oPC)) oPC = GetLocalObject(oDummy, CBD_VAR_OWNER);
    if (!GetIsObjectValid(oPC)) return;
    SendMessageToPC(oPC, CBD_DEBUG_COLOR + "[CBD_DEBUG] " + sMsg + COLOR_END);
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

    // An admin testing the tool gets the diagnostic without touching a console.
    // Resolved here, once, because Admin_CanAdmin is a database read and the
    // damage handler runs per packet.
    // Its own variable, set AND cleared here, so an admin's session never
    // leaves the next player's session dumping packets at them.
    if (Admin_CanAdmin(oPC)) SetLocalInt(oDummy, CBD_VAR_DEBUG_ADMIN, 1);
    else                     DeleteLocalInt(oDummy, CBD_VAR_DEBUG_ADMIN);

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

    // Diagnostic: the tick's own view of the counters, so a tally that is being
    // lost between the damage handler and here is visible as a mismatch with
    // the "counted +N" lines above it.
    if (CBD_IsDebug(oDummy))
        CBD_Debug(oDummy, oPC, "tick round " + IntToString(nRound) +
                  ": atk_rnd=" + IntToString(nAtk) +
                  " dmg_rnd=" + IntToString(nDmg) +
                  " dmg_tot=" + IntToString(GetLocalInt(oDummy, CBD_VAR_DMG_TOT)));
    SetLocalInt(oDummy, CBD_VAR_ATK_RND, 0);
    SetLocalInt(oDummy, CBD_VAR_DMG_RND, 0);

    CBD_Report(oDummy, oPC, "Round " + IntToString(nRound) + "/" +
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

// The end-of-set cue. A full 10-round set finishes with the dummy blowing
// apart - the same visual and the same 6-second cbd_death respawn a real death
// produces, which is exactly why it is used: it is unmistakable across a room,
// and it stops the tester dead. Called on a delay from CBD_EndSession so the
// spoken summary lines (actions on the dummy) get out first.
//
// This is the ONLY death a dummy is ever supposed to have. cbd_spawn's
// EffectImmunity(IMMUNITY_TYPE_DEATH) has to come off for it to land - the
// dummy carries no other immunity effect, so stripping the type is safe and
// avoids caching the effect handle across a 60-second session.
//
// cbd_death does not double-report: CBD_EndSession has already cleared
// CBD_ACTIVE by the time this runs, so the cancel branch there is skipped.
void CBD_SelfDestruct(object oDummy, object oPC, int nToken)
{
    if (!GetIsObjectValid(oDummy)) return;

    // A new session opened in the gap (the replacement dummy is a different
    // object, so this can only be this same dummy being re-engaged): leave it
    // alone rather than killing a run that just started.
    if (GetLocalInt(oDummy, CBD_VAR_TOKEN) != nToken) return;

    // Stop the tester swinging at thin air - the set is over and anything
    // further would land on the corpse or on the replacement.
    if (GetIsObjectValid(oPC)) AssignCommand(oPC, ClearAllActions(TRUE));

    effect e = GetFirstEffect(oDummy);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_IMMUNITY) RemoveEffect(oDummy, e);
        e = GetNextEffect(oDummy);
    }

    // TRUE = spectacular death: the dummy comes apart instead of falling over.
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDeath(TRUE, TRUE), oDummy);
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

    // ...and then it self-destructs. Scheduled before the reporting and the
    // early returns below so that a completed set ALWAYS ends this way, even
    // when the owner has gone or nothing was recorded. Assigned to the module:
    // a delayed command on the dummy would be discarded if it went away first.
    AssignCommand(GetModule(),
        DelayCommand(CBD_DESTRUCT, CBD_SelfDestruct(oDummy, oPC, nToken)));

    if (!GetIsObjectValid(oPC)) return;

    CBD_Report(oDummy, oPC, "Combat test complete (" + IntToString(CBD_ROUNDS) +
               " rounds).");
    CBD_Report(oDummy, oPC, "Attacks per round: " + FloatToString(fApr, 0, 2) +
               "   (" + IntToString(nHitTot) + " hits / " +
               IntToString(nAtkTot) + " attacks)");
    CBD_Report(oDummy, oPC, "Damage per round: " + FloatToString(fDpr, 0, 1) +
               "   (" + IntToString(nDmgTot) + " total)");

    // Nothing happened - don't pollute the leaderboard with idle sessions.
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
    else CBD_Say(oPC, "Combat test cancelled - nothing recorded.");
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

    // One message per session per intruder - the handler fires on every swing.
    string sVar = "CBD_TOLD_" + ObjectToString(oDummy);
    if (GetLocalInt(oPC, sVar) == GetLocalInt(oDummy, CBD_VAR_TOKEN)) return;
    SetLocalInt(oPC, sVar, GetLocalInt(oDummy, CBD_VAR_TOKEN));

    object oOwner = GetLocalObject(oDummy, CBD_VAR_OWNER);
    CBD_Say(oPC, "This combat dummy is in use by " + GetName(oOwner) +
                 ". Wait for the test to finish - your damage is not counted.");
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

    // Stash the attacker FIRST, before any early return: this is the only place
    // the source of a hit is known for certain, and cbd_damage falls back to it
    // when the damage event cannot say who dealt the damage.
    SetLocalObject(oDummy, CBD_VAR_LAST_SRC, OBJECT_SELF);

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

    if (CBD_IsDebug(oDummy))
    {
        // The attack event carries damage fields of its own. These are the
        // values as they stand when this hook runs - devcrit_atk calls us
        // first and adds its bonus dice AFTER, so the difference between this
        // line and the cbd_damage line below is exactly what the rest of the
        // pipeline (devcrit dice, then reduction/resistance) did to the hit.
        CBD_Debug(oDummy, oPC, "attack #" + IntToString(data.iAttackNumber) +
                  ": result=" + IntToString(nRes) +
                  " wtype=" + IntToString(data.iWeaponAttackType) +
                  " sneak=" + IntToString(data.iSneakAttack) +
                  " dmg:" +
                  CBD_DbgField("base",  data.iBase) +
                  CBD_DbgField("bludg", data.iBludgeoning) +
                  CBD_DbgField("pierce", data.iPierce) +
                  CBD_DbgField("slash", data.iSlash) +
                  CBD_DbgField("magic", data.iMagical) +
                  CBD_DbgField("fire",  data.iFire) +
                  CBD_DbgField("cold",  data.iCold) +
                  CBD_DbgField("elec",  data.iElectrical) +
                  CBD_DbgField("acid",  data.iAcid) +
                  CBD_DbgField("sonic", data.iSonic) +
                  CBD_DbgField("div",   data.iDivine) +
                  CBD_DbgField("neg",   data.iNegative) +
                  CBD_DbgField("pos",   data.iPositive));
    }

    if (nRes == 1 || nRes == 3 || nRes == 7 || nRes == 10)
        SetLocalInt(oDummy, CBD_VAR_HIT_TOT,
                    GetLocalInt(oDummy, CBD_VAR_HIT_TOT) + 1);
}
