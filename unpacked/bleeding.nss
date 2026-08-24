
/*************************************************************************
 * OnHeartbeat.txt by Mitchell M. Evans (gonecamping@cox.net)
 *
 * If you use it, or major parts of it, please keep some variety of
 * attribution.  It's only polite :)
 *
 * My Normal Server: Derelict's Server (usually running my custom modules)
 *
 * I've broken this script up functionally.  Since it's the heartbeat
 * function for the entire module, I can see where it might get large and
 * hard to manage otherwise ... as more and more "house rules" are
 * implemented.
 *
 *************************************************************************/

// Server-wide world-state decay/weekly rules are advanced from here. WS_Tick()
// self-throttles to once per minute (via a timestamp in worldstatedb), so
// calling it on every 6s heartbeat pulse is cheap. See worldstate_inc.nss.
#include "worldstate_inc"

// SP_DEV_TOOLS gates the petrification trace below: on for the dev/test realm,
// off for a live season automatically, so the per-PC log lines can never fill a
// production log. Generated from SEASON_ROLE in server.env.
#include "season_prof_inc"

// Wall-clock seconds for the petrification countdown below. NWNX_UTIL_SKIP=n in
// server.env, so the plugin is loaded.
#include "nwnx_util"

/*
 * I like to put all the things I can "tweak" in one place.  You could put
 * each behavior into the function in which it's used, but it's far easier
 * to find them this way.
 */
// --- LOTR petrification timeout (roadmap petrification-timeout-2,
//     petrification-respawn-defect-round-3, -round-4) ---
// The original fix (commit 46aa7efaa1e) edited DoPetrification() in the module's
// x0_i0_spells.nss include, but in-game petrification comes from base-game
// precompiled gaze/flesh-to-stone scripts that inline the STOCK DoPetrification,
// so that edit never ran and PCs stayed petrified indefinitely. This central,
// source-independent watcher runs off the module heartbeat instead: it works no
// matter what applied the petrify. After PETRIFY_TIMEOUT seconds the stone is
// stripped and the PC is killed, with escalating floating-text warnings every
// PETRIFY_WARN_BUCKET seconds. Timing is wall clock, not heartbeat pulses.
//
// Round 3 deleted a GetIsDead() early-return that could never be trusted (a
// petrified PC may or may not read as dead depending on the branch stock
// DoPetrification took), replaced kill-once with a flag of our own, and made the
// timeout strip the stone BEFORE applying EffectDeath. The dev trace from
// 2026-08-20 shows that half working exactly as intended: the ticks count, the
// strip takes (stripped=1 stillStone=0) and the kill lands (isDead=1).
//
// Round 4 measured elapsed time against the wall clock instead of counting
// pulses. Heartbeats land ~6.5s apart in practice, not the nominal 6.0, so
// counting them stretched a "2 minute" timeout to 130 real seconds - the
// "waited 3 minutes" in the report. That part is kept.
//
// Round 4 ALSO made the timeout respawn the player outright (pet_respawn.nss).
// Round 5 (petrification-respawn-defect-round-5) takes that back out on the
// admin's call: the player gets a death panel with a WORKING Respawn button and
// clicks it themselves. pet_respawn.nss is gone; respawn_inc::LOTR_RespawnPC()
// stays, with mod_respawn.nss (the button) as its only caller.
//
// WHAT ROUND 5 IS ACTUALLY CHASING. UAT reports the statue rig in Castle
// Homeless working end to end while a basilisk petrification hangs forever -
// and the admin confirms the full countdown appears in BOTH cases. So detection
// is not the gap, and it never was:
//
//   * every petrification source in the module lands EFFECT_TYPE_PETRIFY.
//     Basilisks carry Spell 485 (SPELL_FLESH_TO_STONE) x6, which fires the
//     base-game precompiled x0_s0_fleshsto.ncs; touch/gaze/breath petrify
//     (x0_s1_petrtouch / x0_s1_petrgaze / x0_s1_petrbreath, shifter
//     x2_s1_petrgaze) all route through the same stock DoPetrification. No hak
//     overrides spells.2da, and no basilisk equipment carries an on-hit petrify.
//   * the countdown reaching the end on a basilisk means HasPetrify() matched
//     and the wall clock ran. The failure is DOWNSTREAM, in the tail.
//
// The tail therefore moved wholesale into pet_timeout.nss, for its own
// instruction budget (a heartbeat that hits the limit under fight load aborts
// silently, which is exactly the observed "works solo, fails in combat" shape)
// and so every step of it can be traced. See pet_timeout.nss for the
// resurrect-then-kill sequence and why the panel has to be a NEW one.
//
// ONE LATENT NON-PETRIFY TRAP, for whoever reads this after a "frozen, but no
// countdown ever started" report: basiliskhard001.uti carries
// ITEM_PROPERTY_ONHITCASTSPELL subtype 136 (ONHIT_CASTSPELL_PARALYZE_2), which
// produces EFFECT_TYPE_PARALYZE and would be invisible to this watcher. No
// creature equips it today. Do NOT widen HasPetrify() to cover paralysis on
// spec - that would put ordinary Hold Person and every cutscene freeze on a
// two-minute death clock.
const float PETRIFY_TIMEOUT    = 120.0;
const int   PETRIFY_WARN_BUCKET = 15;

int HasPetrify(object o)
{
    effect e = GetFirstEffect(o);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_PETRIFY) return TRUE;
        e = GetNextEffect(o);
    }
    return FALSE;
}

void PetrifyLog(string sMsg)
{
    if (SP_DEV_TOOLS) WriteTimestampedLogEntry("[petrify] " + sMsg);
}

void petrifyCheck(object pc)
{
    if (!HasPetrify(pc))
    {
        // Not petrified (never was, or cured e.g. via Stone-to-Flesh, or we just
        // killed them and the strip took) - reset every tracker.
        if (GetLocalInt(pc, "PETRIFY_HB") || GetLocalInt(pc, "PETRIFY_KILLED"))
            PetrifyLog("clear pc=" + GetName(pc));
        DeleteLocalInt(pc, "PETRIFY_T0");
        DeleteLocalInt(pc, "PETRIFY_HB");
        DeleteLocalInt(pc, "PETRIFY_BUCKET");
        DeleteLocalInt(pc, "PETRIFY_KILLED");
        return;
    }

    // THERE IS DELIBERATELY NO GetIsDead() GUARD HERE (roadmap
    // petrification-respawn-defect-round-3). The server runs NWN_DIFFICULTY=3, which
    // takes the bShowPopup branch of stock DoPetrification: a PERMANENT petrify plus
    // PopUpDeathGUIPanel(oTarget, FALSE, TRUE, 40579) - a death panel whose Respawn
    // button the ENGINE disabled. Whether a PC held in that state reads as dead is not
    // something to bet a watcher on - round 2 did, and never counted to anything
    // ("still not killing after 3 min"). Note the dev trace shows isDead=0 on every
    // tick of a statue-rig petrify, so round 3's stated reason (the guard was matching)
    // is NOT established; the guard is gone because it is untrustworthy either way.
    // Kill-once is tracked with our own flag instead, so a corpse is never re-killed.
    if (GetLocalInt(pc, "PETRIFY_KILLED")) return;

    int nHB = GetLocalInt(pc, "PETRIFY_HB") + 1;
    SetLocalInt(pc, "PETRIFY_HB", nHB);

    // WALL CLOCK, not heartbeat counting. Pulses land ~6.5s apart in practice, not
    // the nominal 6.0, so counting them stretched a "2 minute" timeout to 130 real
    // seconds - and further under load. Stamp the first tick and subtract.
    int nNow = NWNX_Util_GetHighResTimeStamp().seconds;
    int nT0  = GetLocalInt(pc, "PETRIFY_T0");
    if (!nT0)
    {
        nT0 = nNow;
        SetLocalInt(pc, "PETRIFY_T0", nT0);
    }
    float fElapsed = IntToFloat(nNow - nT0);

    if (fElapsed >= PETRIFY_TIMEOUT)
    {
        // Everything the timeout does now lives in pet_timeout.nss - the strip,
        // the resurrect that closes the engine's greyed-out death window, and
        // the kill that opens a working one. Nothing heavy stays in the module
        // heartbeat (see the round-5 note at the top of this file).
        SetLocalInt(pc, "PETRIFY_KILLED", TRUE);

        PetrifyLog("timeout pc=" + GetName(pc) +
            " hb=" + IntToString(nHB) +
            " elapsed=" + IntToString(nNow - nT0) +
            " isDead=" + IntToString(GetIsDead(pc)));

        ExecuteScript("pet_timeout", pc);

        DeleteLocalInt(pc, "PETRIFY_T0");
        DeleteLocalInt(pc, "PETRIFY_HB");
        DeleteLocalInt(pc, "PETRIFY_BUCKET");
        return;
    }

    // Warn once per PETRIFY_WARN_BUCKET-second bucket (heartbeat is finer-grained).
    int nBucket = FloatToInt(fElapsed) / PETRIFY_WARN_BUCKET;
    if (nBucket == GetLocalInt(pc, "PETRIFY_BUCKET")) return;
    SetLocalInt(pc, "PETRIFY_BUCKET", nBucket);

    string sMsg;
    if      (fElapsed < 30.0)  sMsg = "A cold, grey numbness creeps up from your feet as stone claims your flesh.";
    else if (fElapsed < 45.0)  sMsg = "Your limbs have turned to unfeeling rock; you can no longer command them.";
    else if (fElapsed < 60.0)  sMsg = "The stiffness climbs past your waist. Panic rises as your body stops answering you.";
    else if (fElapsed < 75.0)  sMsg = "Your chest tightens under solid stone. Each breath is shallower than the last.";
    else if (fElapsed < 90.0)  sMsg = "Your heartbeat slows, muffled beneath layers of stone. Terror is all that still moves in you.";
    else if (fElapsed < 105.0) sMsg = "Darkness crowds the edges of your vision. You feel your heart give one last, straining beat.";
    else                       sMsg = "Your thoughts are stone. Death is only a breath away.";

    // ONE call, not two. FloatingTextStringOnCreature both draws the bobbing
    // text over the PC and writes the same string into that player's chat log,
    // so pairing it with SendMessageToPC printed every countdown line TWICE
    // (roadmap petrification-respawn-defect-round-5). Do not add the
    // SendMessageToPC back.
    FloatingTextStringOnCreature(sMsg, pc, FALSE);

    PetrifyLog("tick pc=" + GetName(pc) +
        " hb=" + IntToString(nHB) +
        " elapsed=" + FloatToString(fElapsed, 0, 1) +
        " isDead=" + IntToString(GetIsDead(pc)));
}


void loadBehaviors()
{
    /*
     * HP at which the player actually dies.  Cannot set below -10 due to
     * hardcoded game restrictions ... so the valid range is 0 to -10.
     * However, if it's zero, that's essentially what NWN does by default.
     */
    SetLocalInt(OBJECT_SELF, "DEATH_TARGET", -10);

    /*
     * If set to TRUE, the player will only grunt on the ground as he or
     * she dies.  If set to false, the player will also call for help
     * periodically.
     */
    SetLocalInt(OBJECT_SELF, "PLAYER_ONLY_GRUNTS_WHILE_DYING", FALSE);
}


/*
 * Checks the pc object to determine if the hit points are zero or less.
 * If so, and the player has not actually died, this function inflicts one
 * point of damage to the PC, and makes an appropriate sound (grunt, call for
 * aid, etc).  When the hit points have reached the desired target, this
 * function sends a death event to the pc object.
 */
void bleedCheck(object pc)
{
    // make sure a valid PC object was passed in
    if (!GetIsPC(pc))
        return;

    // get desired behaviors
    int DEATH_TARGET = GetLocalInt(OBJECT_SELF, "DEATH_TARGET");
    int PLAYER_ONLY_GRUNTS_WHILE_DYING = GetLocalInt(OBJECT_SELF, "PLAYER_ONLY_GRUNTS_WHILE_DYING");

    int hp = GetCurrentHitPoints(pc);

    // make sure pc is bleeding, and not already dead
    if ((hp <= 0) && (hp > DEATH_TARGET))
    {
        // damage pc
        effect dmg = EffectDamage(1);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, dmg, pc);
        int which = d6();

        // if the DM wants only grunts, only use first 3 cases in the
        // switch statement below
        if (PLAYER_ONLY_GRUNTS_WHILE_DYING)
            which = FloatToInt(IntToFloat(which) / 2.0 + 0.5);

        switch (which)
        {
            case 1:
                PlayVoiceChat(VOICE_CHAT_PAIN1, pc);
                break;

            case 2:
                PlayVoiceChat(VOICE_CHAT_PAIN2, pc);
                break;

            case 3:
                PlayVoiceChat(VOICE_CHAT_PAIN3, pc);
                break;

            case 4:
                PlayVoiceChat(VOICE_CHAT_HEALME, pc);
                break;

            case 5:
                PlayVoiceChat(VOICE_CHAT_NEARDEATH, pc);
                break;

            case 6:
                PlayVoiceChat(VOICE_CHAT_HELP, pc);
                break;
        }

    }
    else if (hp <= DEATH_TARGET)
    {
        // pc bled to death
        effect death = EffectDeath(FALSE, FALSE);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, death, pc);
    }
}


/*
 * OnHeartbeat main
 */
void main()
{
    // load up desired behaviors for all OnHeartbeat scripts
    loadBehaviors();

    // enumerate all PCs, calling bleedCheck on each
    // if you want to add more / other scripts that act on all players
    // every heartbeat, this is the place to do it ... just put a call
    // to them after (or before) bleedCheck, within the while loop.
    object pc = GetFirstPC();

    while (GetIsObjectValid(pc))
    {
        bleedCheck(pc);
        petrifyCheck(pc);

        pc = GetNextPC();
    }

    // Advance server-wide world-state rules (decay / weekly resets). Self-
    // throttled to ~1/min inside WS_Tick(); a no-op on pulses in between and
    // when no rules are registered.
    WS_Tick();
}


