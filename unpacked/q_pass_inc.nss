// q_pass_inc.nss — "Pass the Pass" Misty Mountains escort (roadmap: pass-the-pass)
//
// T2 (L10+) daily escort quest, journal tag "pass_pass". A caravan-master
// waits at the western foot of the High Pass (Foothills of the Misty
// Mountains) and hires the PC to see his wagons across to the eastern
// waystation (the far Misty Mountains ledge). The PC picks a difficulty at
// dialogue; the reward scales as nDiff * QPASS_GOLD_PER gold plus nDiff *
// QPASS_XP_PER XP. On the hardest run a Stone-Giant (q_pass_gnt, a plot-safe
// CR-25 clone of the ordinary Misty Mountains giant "mgiant") ambushes the
// caravan mid-pass. One escort per real calendar day (quest_cd_inc:
// QCD_IsDoneToday gates the offer, QCD_Stamp fires on turn-in).
//
// BOUNDED (no walking-companion escort AI): accept at the giver, an ambush
// scaled by difficulty spawns at waypoint AP_passthepass_2 mid-pass, and the
// quartermaster on the far side pays out when reached. Reaching the far side
// is the whole objective; the ambush is the danger, not a hard fail-state.
//
// Waypoint tags (hyphen-less roadmap id; MUST match the admin-action entries):
//   AP_passthepass_1  giver spawn        (Foothills of the Misty Mountains)
//   AP_passthepass_2  ambush spawn       (The Misty Mountains, mistymountainsa)
//   AP_passthepass_3  quartermaster spawn(The Misty Mountains, mistymountainsb)
// Everything no-ops gracefully until the admin places the waypoints, so the
// module ships and compiles before any placement exists.
//
// Session state (locals on the PC, set at accept, cleared at turn-in):
//   QPASS_ACTIVE  1 while an escort is in progress (blocks re-accept, gates turn-in)
//   QPASS_DIFF    the chosen difficulty 1..3 (drives payout + ambush composition)
//
// Custom token: 6395 = "come back tomorrow" countdown on the giver.

#include "quest_cd_inc"

const string QPASS_QUEST    = "pass_pass";  // questcddb key + journal tag
const int    QPASS_GOLD_PER = 200;          // gold reward = nDiff * this
const int    QPASS_XP_PER   = 150;          // xp   reward = nDiff * this
const int    QPASS_MAXDIFF  = 3;            // hardest tier (Stone-Giant ambush)

// ------------------------------------------------------------
// Small accessors.

int QPASS_Diff(object oPC)   { return GetLocalInt(oPC, "QPASS_DIFF"); }
int QPASS_Active(object oPC) { return GetLocalInt(oPC, "QPASS_ACTIVE"); }

// Seconds until the next UTC midnight (when QCD_IsDoneToday flips back). From
// SQLite so there is no game-clock drift, matching QCD_IsDoneToday's date().
int QPASS_SecsToTomorrow()
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT CAST(strftime('%s', date('now','+1 day')) AS INTEGER)"
        + " - CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// ------------------------------------------------------------
// Ambush. Spawns a difficulty-scaled warband at AP_passthepass_2 (mid-pass).
// No-ops when the waypoint is unplaced. Rate is limited naturally: a PC can
// only accept once per day and cannot re-accept while an escort is active, so
// each player triggers at most one ambush per day.

void QPASS_Mob(string sResRef, location lLoc)
{
    object oM = CreateObject(OBJECT_TYPE_CREATURE, sResRef, lLoc);
    if (GetIsObjectValid(oM))
        SetLocalInt(oM, "QPASS_AMBUSH", 1);   // tag for later cleanup/inspection
}

void QPASS_SpawnAmbush(int nDiff)
{
    object oWP = GetWaypointByTag("AP_passthepass_2");
    if (!GetIsObjectValid(oWP)) return;       // no-op until the admin places it
    location lLoc = GetLocation(oWP);

    int i;
    if (nDiff <= 1)
    {
        // Easy: a rabble of goblin-kin.
        for (i = 0; i < 3; i++) QPASS_Mob("bugbeara001", lLoc);
    }
    else if (nDiff == 2)
    {
        // Normal: goblin soldiers led by a bigger brute.
        for (i = 0; i < 3; i++) QPASS_Mob("bugchiefa001", lLoc);
        QPASS_Mob("bugbearboss001", lLoc);
    }
    else
    {
        // Hard: soldiers, wargs, and a Stone-Giant of the High Pass.
        for (i = 0; i < 4; i++) QPASS_Mob("bugchiefa001", lLoc);
        for (i = 0; i < 2; i++) QPASS_Mob("q_brn_warg", lLoc);
        QPASS_Mob("q_pass_gnt", lLoc);
    }
}

// ------------------------------------------------------------
// Accept (ActionTaken from the difficulty replies q_pass_d1/d2/d3).

void QPASS_Begin(object oPC, int nDiff)
{
    if (QCD_IsDoneToday(oPC, QPASS_QUEST)) return;  // already ran today
    if (QPASS_Active(oPC)) return;                  // already escorting
    if (nDiff < 1) nDiff = 1;
    if (nDiff > QPASS_MAXDIFF) nDiff = QPASS_MAXDIFF;

    SetLocalInt(oPC, "QPASS_ACTIVE", 1);
    SetLocalInt(oPC, "QPASS_DIFF", nDiff);
    AddJournalQuestEntry(QPASS_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    QPASS_SpawnAmbush(nDiff);

    FloatingTextStringOnCreature(
        "The caravan sets out. Cross the high pass to the eastern waystation.",
        oPC, FALSE);
}

// ------------------------------------------------------------
// Turn-in (ActionTaken from the quartermaster's accepting reply q_pass_pay).
// Guarded so it can never pay twice in a day or without an active escort.

void QPASS_TurnIn(object oPC)
{
    if (!QPASS_Active(oPC)) return;
    int nDiff = QPASS_Diff(oPC);
    if (nDiff < 1) nDiff = 1;

    DeleteLocalInt(oPC, "QPASS_ACTIVE");
    DeleteLocalInt(oPC, "QPASS_DIFF");

    if (QCD_IsDoneToday(oPC, QPASS_QUEST)) return;  // paranoid double-pay guard
    QCD_Stamp(oPC, QPASS_QUEST);

    GiveGoldToCreature(oPC, nDiff * QPASS_GOLD_PER);
    GiveXPToCreature(oPC, nDiff * QPASS_XP_PER);
    AddJournalQuestEntry(QPASS_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    FloatingTextStringOnCreature(
        "The caravan is safe across the pass. The quartermaster counts out your pay.",
        oPC, FALSE);
}
