// jb_buff_inc.nss - the reward for sitting and listening to the jukebox.
//
// TWO STATES, AND THE CLOCK ONLY RUNS IN THE SECOND ONE
//
//   LISTENING  - you are in the room, songs are finishing, and credit is piling
//                up. Nothing is applied and NOTHING EXPIRES.
//   CARRYING   - you have left the room. The credit is spent, once, into a buff
//                of a size and a duration both scaled by how long you listened,
//                and that buff now runs down.
//
// THE FIRST BUILD GOT THIS WRONG AND THE BUG IS WORTH RECORDING, because the
// arithmetic hid it. Credit decayed from the moment it was granted, while the
// player was still sitting there listening. With JB_BUFF_FULL_SEC equal to
// JB_BUFF_DUR_SEC, a credit of c seconds buys a window of exactly c seconds -
// so listening for a further t seconds decayed the credit by t and added t.
// Net zero. The credit was pinned at roughly one song's length forever and the
// cap was unreachable no matter how long anyone sat there. The buffs cancelled
// themselves out.
//
// Hence: accrual adds to the RAW stored credit and never decays it, and the
// expiry timestamp is not written until the player leaves. This is also what
// the roadmap item asked for in the first place - "the buff applies once you
// leave the area and the server confirms the buff info to the player".
//
// HOW LEAVING IS DETECTED, without displacing anything
//
// Every jukebox area already had an OnExit owner (cleanup, d_purge) or none at
// all. Rather than replace or chain those, the two shared scripts call
// jb_area_exit through ExecuteScript, and the three areas that had no OnExit
// point at jb_area_exit directly. The call in the shared scripts is guarded by
// a plain PC local so that an area exit anywhere else in the module costs one
// GetLocalInt and no SQL.
//
// A LOGOUT IS NOT AN EXIT. Area OnExit does not fire when a player disconnects,
// so JB_RefreshBuff() also converts a listening row to a buff at login when the
// player comes back somewhere other than the room they were listening in.
//
// THE NUMBERS SHIP DELIBERATELY LOW. The roadmap item asks for +10 attack, +10
// damage and +10 to every ability score. The mechanic here is exactly that one;
// the caps are constants, and raising them is a tuning decision rather than a
// code change. Two reasons to start small: this realm raises the engine attack
// ceiling to 40 (NWN_MAX_ATTACK_BONUS) and the ledger can sum past it without
// telling you, and +10 to all six abilities for ten minutes is a large thing to
// hand out for standing still.
//
// ATTACK AND DAMAGE GO THROUGH THE LEDGER, NOT THROUGH EffectAttackIncrease.
// Same-type attack effects do not stack in NWN - the engine keeps the highest
// and discards the rest - so an unpooled bonus would not merely fail to add, it
// would SUPPRESS every smaller pooled bonus for as long as it lasted. That is
// how Legendary Prowess's +5 silently swallowed Bard Song. bonus_pool_inc.nss
// is the only place those two effects are built, and tests/check_bonus_pool.py
// fails the repack if anything else builds them.
//
// THE ABILITY BONUSES ARE NOT POOLED, AND THAT HAS A CONSEQUENCE WORTH KNOWING:
// EffectAbilityIncrease is max-of per ability just as the attack channel is, so
// a jukebox +2 Strength and a Bull's Strength do NOT add - the larger wins.
// There is no ability ledger to register with, so this is a real limitation
// rather than a bug.
//
// THE STORED ROW IS AUTHORITATIVE; THE EFFECTS ARE A PROJECTION OF IT. Plain
// DURATION_TYPE_TEMPORARY effects are scrubbed by the engine's rest pass and
// never survive a logout, so jb_buff is the record and the effects are
// re-derived from it at login and after a rest. That is the pw_inc.nss model
// (pw_inc.nss:9-15), and the effects are tagged so stripping only takes ours.
//
// THE APPROXIMATION IN ACCRUAL. Credit is granted when a track ENDS, to whoever
// is in the room, for that track's full length - there is no per-player
// attendance timer, because the module has no scheduler and heartbeats are not
// its style. So walking in halfway through a song is credited for all of it and
// leaving halfway is credited for none of it. Over a sitting these cancel.
// Credit only accrues while a PAID song is playing, so an empty tavern cannot
// be idled for a buff.
#include "jb_db"
#include "bonus_pool_inc"
#include "color"

// ------------------------------------------------------------------ tuning --

const int JB_BUFF_CAP      = 2;    // the cap the roadmap item puts at 10
const int JB_BUFF_FULL_SEC = 600;  // listening time that earns the full cap
const int JB_BUFF_DUR_SEC  = 600;  // how long the full buff lasts once earned
const int JB_BUFF_STEP_SEC = 60;   // the "1 minute increments" of the LERP

const string JB_EFFECT_TAG = "jb_listen_buff";

// PC local, the cheap guard the shared OnExit scripts test before doing any
// work. cleanup.nss and d_purge.nss spell this literally because they do not
// include this file; tests/check_jukebox_queue.py asserts the two agree.
const string JB_LISTENING = "jb_listening";

// ------------------------------------------------------------------- shape --

// How big the bonus is for a given amount of listening, in 1-minute steps.
int JB_BuffMagnitude(int nCreditedSec)
{
    if (nCreditedSec <= 0) return 0;
    int nSteps = nCreditedSec / JB_BUFF_STEP_SEC;
    int nMax   = JB_BUFF_FULL_SEC / JB_BUFF_STEP_SEC;
    if (nSteps > nMax) nSteps = nMax;
    return (JB_BUFF_CAP * nSteps) / nMax;
}

// How long it lasts, in seconds, for that same amount of listening.
int JB_BuffDuration(int nCreditedSec)
{
    if (nCreditedSec <= 0) return 0;
    int nSteps = nCreditedSec / JB_BUFF_STEP_SEC;
    int nMax   = JB_BUFF_FULL_SEC / JB_BUFF_STEP_SEC;
    if (nSteps > nMax) nSteps = nMax;
    return (JB_BUFF_DUR_SEC * nSteps) / nMax;
}

// ---------------------------------------------------------------- listening --

int JB_Credited(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT credited_sec FROM jb_listen WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// The area they were listening in, or "" - used at login to tell "still in the
// tavern" from "logged out there and came back somewhere else".
string JB_ListenArea(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT area FROM jb_listen WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetString(q, 0) : "";
}

void JB_SetCredited(object oPC, int nSec, string sArea, int nWhen)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "INSERT INTO jb_listen(uuid, credited_sec, area, updated_at) " +
        "VALUES(@u,@c,@a,@w) ON CONFLICT(uuid) DO UPDATE SET " +
        "credited_sec = @c, area = @a, updated_at = @w");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nSec);
    SqlBindString(q, "@a", sArea);
    SqlBindInt(q, "@w", nWhen);
    SqlStep(q);
}

void JB_ClearListening(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "DELETE FROM jb_listen WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);
    DeleteLocalInt(oPC, JB_LISTENING);
}

// ----------------------------------------------------------------- carrying --

int JB_BuffMag(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT mag FROM jb_buff WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

int JB_BuffLeft(object oPC, int nNow)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT expires_at - @n FROM jb_buff WHERE uuid = @u");
    SqlBindInt(q, "@n", nNow);
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return 0;
    int nLeft = SqlGetInt(q, 0);
    return (nLeft > 0) ? nLeft : 0;
}

void JB_ClearBuffRow(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "DELETE FROM jb_buff WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);
}

// -------------------------------------------------------------- projection --

void JB_StripBuff(object oPC)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == JB_EFFECT_TAG) RemoveEffect(oPC, e);
        e = GetNextEffect(oPC);
    }
    BPool_Clear(oPC, BPOOL_CH_ATTACK, BPOOL_SRC_MUSIC);
    BPool_Clear(oPC, BPOOL_CH_DAMAGE, BPOOL_SRC_MUSIC);
}

// Rebuild the effects from the stored buff row. Idempotent, and cheap for a
// character who has never used a jukebox: one SELECT and out.
void JB_ApplyBuff(object oPC)
{
    if (!GetIsPC(oPC)) return;

    int nNow  = JB_Now();
    int nMag  = JB_BuffMag(oPC);
    int nLeft = JB_BuffLeft(oPC, nNow);

    JB_StripBuff(oPC);

    if (nMag <= 0 || nLeft <= 0)
    {
        if (nMag > 0) JB_ClearBuffRow(oPC);   // expired; tidy the row away
        return;
    }

    float fDur = IntToFloat(nLeft);

    // Attack and damage through the ledger - never EffectAttackIncrease here.
    BPool_Set(oPC, BPOOL_CH_ATTACK, BPOOL_SRC_MUSIC, nMag, fDur);
    BPool_Set(oPC, BPOOL_CH_DAMAGE, BPOOL_SRC_MUSIC, nMag, fDur);

    // Abilities are not pooled (there is no ability ledger), so they are applied
    // directly - tagged, so JB_StripBuff only ever takes ours back off.
    int nAbility;
    for (nAbility = ABILITY_STRENGTH; nAbility <= ABILITY_CHARISMA; nAbility++)
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
            TagEffect(EffectAbilityIncrease(nAbility, nMag), JB_EFFECT_TAG),
            oPC, fDur);
}

// ------------------------------------------------------------------ accrual --

// Credit everyone in the room for a song that just finished. Called from the
// queue when a paid track ends.
//
// NOTE the raw JB_Credited() here rather than anything time-adjusted: while a
// player is listening their credit does not decay. That is the whole fix.
void JB_CreditListeners(object oArea, int nSeconds)
{
    if (!GetIsObjectValid(oArea) || nSeconds <= 0) return;

    int nNow = JB_Now();
    string sArea = JB_AreaKey(oArea);

    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        if (GetArea(oPC) == oArea && !GetIsDM(oPC))
        {
            int nCred = JB_Credited(oPC) + nSeconds;
            if (nCred > JB_BUFF_FULL_SEC) nCred = JB_BUFF_FULL_SEC;

            JB_SetCredited(oPC, nCred, sArea, nNow);
            SetLocalInt(oPC, JB_LISTENING, TRUE);
        }
        oPC = GetNextPC();
    }
}

// ------------------------------------------------------------------- payout --

// Spend the listening credit into a buff. Called when the player leaves the
// room they were listening in - and at login, if they logged out in it.
//
// Takes the BETTER of what they already carry and what they just earned, rather
// than summing: two sittings should not stack into something the cap was never
// meant to allow, and the player should never be punished for walking out with
// a fresh, smaller drink.
void JB_GrantOnLeave(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nCred = JB_Credited(oPC);
    JB_ClearListening(oPC);
    if (nCred <= 0) return;

    int nMag = JB_BuffMagnitude(nCred);
    int nDur = JB_BuffDuration(nCred);
    if (nMag <= 0 || nDur <= 0) return;

    int nNow = JB_Now();
    int nHaveMag = JB_BuffMag(oPC);
    int nHaveLeft = JB_BuffLeft(oPC, nNow);

    if (nHaveMag > nMag || (nHaveMag == nMag && nHaveLeft > nDur))
    {
        // What they are already carrying is better; leave it alone and say
        // nothing, rather than quietly shortening it.
        JB_ApplyBuff(oPC);
        return;
    }

    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "INSERT INTO jb_buff(uuid, mag, expires_at) VALUES(@u,@m,@e) " +
        "ON CONFLICT(uuid) DO UPDATE SET mag = @m, expires_at = @e");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindInt(q, "@m", nMag);
    SqlBindInt(q, "@e", nNow + nDur);
    SqlStep(q);

    JB_ApplyBuff(oPC);

    SendMessageToPC(oPC, ColorString(
        "[Jukebox] You carry the music out with you - you stand a little "
        + "taller for it (+" + IntToString(nMag) + " to your swing, your blows "
        + "and every measure of you) for the next " + IntToString(nDur / 60)
        + " minute" + ((nDur / 60 == 1) ? "" : "s") + ".", COLOR_GREEN));
}

// Called from jb_area_exit when a PC leaves an area. Only pays out if this is
// the room they were actually listening in - walking out of some other area
// while carrying credit must not cash it in early.
void JB_OnLeaveArea(object oPC, object oArea)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (!GetLocalInt(oPC, JB_LISTENING)) return;
    if (JB_ListenArea(oPC) != JB_AreaKey(oArea)) return;

    JB_GrantOnLeave(oPC);
}

// Login and after-rest re-derivation. Cheap and idempotent.
void JB_RefreshBuff(object oPC)
{
    if (!GetIsPC(oPC)) return;

    // A reconnecting PC comes back from the server TURD with its locals intact
    // (mod_cliententer.nss:225-232), so this guard local must never be trusted
    // across a login - it is rebuilt from the row below.
    DeleteLocalInt(oPC, JB_LISTENING);

    string sListen = JB_ListenArea(oPC);
    if (sListen != "")
    {
        if (sListen == JB_AreaKey(GetArea(oPC)))
            // Still in the tavern: keep listening, pay out when they leave.
            SetLocalInt(oPC, JB_LISTENING, TRUE);
        else
            // They logged out listening and came back elsewhere. Area OnExit
            // never fired, so settle up now rather than strand the credit.
            JB_GrantOnLeave(oPC);
    }

    JB_ApplyBuff(oPC);
}
