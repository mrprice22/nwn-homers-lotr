
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
// matter what applied the petrify. After PETRIFY_TIMEOUT seconds the PC is killed
// via EffectDeath and then respawned at the bind point by pet_respawn, with
// escalating warnings both in chat and as floating text every PETRIFY_WARN_BUCKET
// seconds. Timing is wall clock, not heartbeat pulses (see round 4 below).
//
// Round 3 deleted a GetIsDead() early-return that could never be trusted (a
// petrified PC may or may not read as dead depending on the branch stock
// DoPetrification took), replaced kill-once with a flag of our own, and made the
// timeout strip the stone BEFORE applying EffectDeath. The dev trace from
// 2026-08-20 shows that half working exactly as intended: the ticks count, the
// strip takes (stripped=1 stillStone=0) and the kill lands (isDead=1).
//
// Round 4 (petrification-respawn-defect-round-4) fixes the two things that
// trace also exposed:
//
//   * The player was still stuck. The engine had ALREADY popped its own death
//     window with Respawn greyed out at petrify time, and re-popping the panel
//     from ondeath020 does not refresh a panel the client is already showing -
//     hence "I can't respawn, but after exiting and re-entering the game
//     everything is fine". So the timeout no longer asks the player to click
//     anything: it hands off to pet_respawn, which resurrects them at the bind
//     point. The engine closes the death window on its own once they are alive.
//   * The countdown was long. Heartbeat pulses are not exactly 6.0s apart -
//     the trace ran 130 real seconds over 20 pulses (~6.5s each), which is the
//     "waited 3 minutes" in the report. Elapsed time is now measured against
//     the wall clock, so PETRIFY_TIMEOUT means 120 REAL seconds under any load.
//
// Grace before the auto-respawn, so a Raise Dead in the last few seconds wins;
// pet_respawn re-checks GetIsDead() before it moves anybody.
const float PETRIFY_RESPAWN_GRACE = 4.0;
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

// Remove the petrification. RemoveEffect on ANY component of a linked effect drops
// the whole link, so this also takes the VFX_DUR_CESSATE_NEGATIVE that stock
// DoPetrification links to the EffectPetrify. Returns how many were removed, which
// the trace logs -- a zero here on a PC that HasPetrify() said was stone is the
// signature of an effect we cannot reach from script.
int StripPetrify(object o)
{
    int nRemoved = 0;
    effect e = GetFirstEffect(o);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_PETRIFY)
        {
            RemoveEffect(o, e);
            nRemoved++;
        }
        e = GetNextEffect(o);
    }
    return nRemoved;
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
        // ORDER MATTERS. Strip the stone FIRST, kill SECOND. EffectDeath on a creature
        // the engine still holds as a statue is the likely no-op, and a corpse that is
        // still carrying the petrify is the other candidate for the greyed-out Respawn
        // button. Stripping first leaves an ordinary living PC for EffectDeath to kill
        // through the normal pipeline (ondeath020 -> death/respawn GUI).
        int nStripped = StripPetrify(pc);
        SetLocalInt(pc, "PETRIFY_KILLED", TRUE);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDeath(), pc);

        // Kill first (so ondeath020 still runs - death amulet, BIC export), then put
        // them back on their feet ourselves. See pet_respawn.nss for why the player is
        // NOT left to click the death window's Respawn button: the panel on their
        // screen is the one the engine disabled at petrify time, and it does not
        // refresh. The grace lets a Raise Dead land first; pet_respawn re-checks.
        DelayCommand(PETRIFY_RESPAWN_GRACE, ExecuteScript("pet_respawn", pc));

        PetrifyLog("timeout kill pc=" + GetName(pc) +
            " hb=" + IntToString(nHB) +
            " elapsed=" + IntToString(nNow - nT0) +
            " stripped=" + IntToString(nStripped) +
            " stillStone=" + IntToString(HasPetrify(pc)) +
            " isDead=" + IntToString(GetIsDead(pc)));

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

    SendMessageToPC(pc, sMsg);
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


