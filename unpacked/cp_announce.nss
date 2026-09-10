// cp_announce -- Crash Party: fire the next countdown line, by hand.
//
// Control-room placard and rest menu, via CP_DmUser().
//
// ## The countdown runs itself once you start it
//
// One press sends "starts in one hour" AND schedules the rest: thirty minutes
// later the next line, twenty after that, ten after that, then the doors-open
// shout, after which the chain ends. So a DM kicks it off and forgets about it.
//
// Pressing it again still works and is the reason the generation guard exists
// (CP_AnnounceSchedule / cp_anntick.nss): a manual press fires the next line
// immediately and re-schedules from there, and the pending automatic tick
// retires instead of announcing the same line twice. That is the "DM got on
// late" case -- press it as often as you need to catch up.
//
// Past the doors opening it falls through to a repeatable "still going" shout
// that is manual only, because a party that nags every half hour is worse than
// one that does not.
//
// Text is deliberately season-neutral: bin/season-brand.py owns the season
// strings and tests/check_season_brand.py fails the repack on a hardcoded one.

#include "cp_dm_inc"

void main()
{
    object oPC = CP_DmUser();   // placard OR rest menu
    if (!CP_DmGate(oPC)) return;

    int nStep = GetLocalInt(GetModule(), CP_ANN_STEP);
    CP_AnnounceFire();
    CP_AnnounceSchedule();

    int nGap = CP_AnnounceGap(nStep);
    SendMessageToPC(oPC, "Announcement " + IntToString(nStep) + " sent to "
        + IntToString(CP_OnlineCount()) + " player(s)."
        + (nGap > 0
           ? " Next one automatically in " + IntToString(nGap) + " minutes."
           : " That is the end of the countdown; further presses repeat the "
             + "'still going' shout."));
}
