// cp_peak -- Crash Party: watch the live player count and announce a new record.
//
// Scheduled from mod_cliententer.nss. Client enter is the ONLY moment the online
// count can rise, so checking here is both exact and free -- no heartbeat, no
// polling. (The count also falls on client exit, but a fall can never set a
// record, so there is nothing to do there.)
//
// The record itself lives in the crashpartydb campaign DB, seeded from the wiki's
// own peak-concurrent figure. That number is computed by nwn_wiki's activity
// renderer from real log join/leave events, so this in-game counter is a
// motivational mirror of it, not the authority -- the wiki still decides what the
// record officially is at the next refresh.
//
// Runs all the time, not just during the party: a record set on an ordinary
// Tuesday is still a record, and the sign should say so.

#include "cp_inc"

// The figure to beat when the table is empty. Season 2's peak as recorded on the
// wiki's Player Activity page on 2026-09-07. Only ever used to seed an empty DB;
// once a real count exceeds it the DB is the source of truth.
const int CP_PEAK_SEED = 8;

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nNow  = CP_OnlineCount();
    int nPeak = CP_GetPeak();
    if (nPeak <= 0) nPeak = CP_PEAK_SEED;

    if (nNow <= nPeak) return;

    CP_SetPeak(nNow);
    CP_Broadcast("*** NEW SERVER RECORD: " + IntToString(nNow)
        + " players online at once! (previous best " + IntToString(nPeak) + ") ***",
        COLOR_YELLOW);
}
