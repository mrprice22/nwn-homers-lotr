// jb_buff_inc.nss - the reward for sitting and listening to the jukebox.
//
// Listen while a paid song plays and you build up credit. The credit scales
// both the SIZE of the bonus and how long it lasts, so ten minutes of listening
// is worth the cap for ten minutes and one minute is worth a tenth of it for
// one minute - the roadmap item's "LERP down in 1 minute increments".
//
// THE NUMBERS SHIP DELIBERATELY LOW. The roadmap item asks for +10 attack, +10
// damage and +10 to every ability score. The mechanic here is exactly that one;
// the caps are constants set to JB_BUFF_CAP, and raising them is a tuning
// decision rather than a code change. Two reasons to start small: this realm
// raises the engine attack ceiling to 40 (NWN_MAX_ATTACK_BONUS) and the ledger
// can sum past it without telling you, and +10 to all six abilities for ten
// minutes is a large thing to hand out for standing still.
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
// rather than a bug: expect the jukebox's ability half to be invisible to a
// character already carrying a bigger ability buff.
//
// THE STORED CREDIT IS AUTHORITATIVE; THE EFFECTS ARE A PROJECTION OF IT.
// Plain DURATION_TYPE_TEMPORARY effects are scrubbed by the engine's rest pass
// and never survive a logout, so the row in jb_listen is the record and the
// effects are re-derived from it at every boundary where the engine may have
// wiped them. That is the pw_inc.nss model (pw_inc.nss:9-15), and the effects
// are tagged so that stripping only ever takes our own.
//
// HOW CREDIT IS ACCRUED, AND THE APPROXIMATION IN IT
//
// Credit is granted when a track ENDS, to whoever is in the room, for that
// track's full length. There is deliberately no per-player attendance timer:
// the module has no scheduler, heartbeats are not its style, and every one of
// the eight jukebox areas already has its own OnEnter script that a generic
// hook would have to displace.
//
// The approximation is therefore that someone who walks in halfway through a
// song is credited for all of it, and someone who leaves halfway is credited
// for none of it. Over a sitting those errors are small and they cancel; over a
// single song the second one is the harsher, which is the right way round for a
// reward. Credit only accrues while a PAID song is playing, so an empty tavern
// cannot be idled for it.
#include "jb_db"
#include "bonus_pool_inc"
#include "color"

// ------------------------------------------------------------------ tuning --

const int JB_BUFF_CAP      = 2;    // the cap the roadmap item puts at 10
const int JB_BUFF_FULL_SEC = 600;  // listening time that earns the full cap
const int JB_BUFF_DUR_SEC  = 600;  // how long the full buff lasts once earned
const int JB_BUFF_STEP_SEC = 60;   // the "1 minute increments" of the LERP

const string JB_EFFECT_TAG = "jb_listen_buff";
const string JB_BUFF_SEEN  = "jb_buff_seen";  // PC local: last magnitude told to them

// ------------------------------------------------------------------ storage --

// The jb_listen table is created by JB_InitDb() in jb_db.nss, with the rest of
// the jukebox schema - one bootstrap, called from onmoduleload, rather than a
// second one that a future reader would have to remember exists.

int JB_Credited(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT credited_sec FROM jb_listen WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

int JB_CreditedAt(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT updated_at FROM jb_listen WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

void JB_SetCredited(object oPC, int nSec, int nWhen)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "INSERT INTO jb_listen(uuid, credited_sec, updated_at) VALUES(@u,@c,@w) " +
        "ON CONFLICT(uuid) DO UPDATE SET credited_sec = @c, updated_at = @w");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindInt(q, "@c", nSec);
    SqlBindInt(q, "@w", nWhen);
    SqlStep(q);
}

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

// How much of the credit is left at a given moment. The credit itself decays
// over the buff's own window, which is what makes the effect re-derivable after
// a logout: (stored credit, stored timestamp) is enough to know what the player
// should have right now.
int JB_LiveCredit(object oPC, int nNow)
{
    int nCred = JB_Credited(oPC);
    if (nCred <= 0) return 0;

    int nElapsed = nNow - JB_CreditedAt(oPC);
    if (nElapsed < 0) nElapsed = 0;            // clock moved; be generous

    int nWindow = JB_BuffDuration(nCred);
    if (nElapsed >= nWindow) return 0;

    // Decay the credit in step with the window, so the bonus walks down in the
    // same 1-minute increments it walked up in.
    return (nCred * (nWindow - nElapsed)) / nWindow;
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

// Rebuild the effects from the stored credit. Idempotent, and cheap for a
// character with no row: one SELECT and out.
void JB_RefreshBuff(object oPC)
{
    if (!GetIsPC(oPC)) return;

    int nNow  = JB_Now();
    int nLive = JB_LiveCredit(oPC, nNow);
    int nMag  = JB_BuffMagnitude(nLive);

    JB_StripBuff(oPC);

    if (nMag <= 0)
    {
        DeleteLocalInt(oPC, JB_BUFF_SEEN);
        return;
    }

    float fDur = IntToFloat(JB_BuffDuration(nLive));
    if (fDur <= 0.0) return;

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

// In-character confirmation, and only when the number has actually changed -
// a line per song would be noise in a tavern.
void JB_TellBuff(object oPC, int nMag, int nDurSec)
{
    if (GetLocalInt(oPC, JB_BUFF_SEEN) == nMag) return;
    SetLocalInt(oPC, JB_BUFF_SEEN, nMag);
    if (nMag <= 0) return;

    SendMessageToPC(oPC, ColorString(
        "[Jukebox] The music stays with you - you carry yourself better for it "
        + "(+" + IntToString(nMag) + " to your swing, your blows and every "
        + "measure of you) for the next " + IntToString(nDurSec / 60)
        + " minute" + ((nDurSec / 60 == 1) ? "" : "s") + ".", COLOR_GREEN));
}

// ----------------------------------------------------------------- accrual --

// Credit everyone in the room for a song that just finished. Called from the
// queue when a paid track ends - see the approximation note in the header.
void JB_CreditListeners(object oArea, int nSeconds)
{
    if (!GetIsObjectValid(oArea) || nSeconds <= 0) return;

    int nNow = JB_Now();
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        if (GetArea(oPC) == oArea && !GetIsDM(oPC))
        {
            // Build on what is still live rather than on the raw stored number,
            // so a player who listened, wandered off and came back does not
            // resume from a credit that has already expired.
            int nCred = JB_LiveCredit(oPC, nNow) + nSeconds;
            if (nCred > JB_BUFF_FULL_SEC) nCred = JB_BUFF_FULL_SEC;

            JB_SetCredited(oPC, nCred, nNow);
            JB_RefreshBuff(oPC);
            JB_TellBuff(oPC, JB_BuffMagnitude(nCred), JB_BuffDuration(nCred));
        }
        oPC = GetNextPC();
    }
}
