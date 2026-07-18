// q_bard_inc.nss -- "Tales That Live Forever", Bard class-line I
// (roadmap: bard-line-early)
//
// PREFIX NOTE: this line uses q_bard_* rather than the obvious q_brd_*. The
// module already ships the boss-respawn tracker under the bare brd_* prefix
// (brd_db, brd_open_*, brd_vis_*, brd_sign.dlg -- see CLAUDE-boss-tracker.md),
// and q_brd_* sitting next to it in a flat single-directory source tree is an
// invitation to grep the wrong family. q_bard_* is unambiguous and every
// resref stays inside the 16-character limit.
//
// The early nodes (L1 / L8 / L15) of the Bard line. Lindir of the Hall of Fire
// keeps the Rivendell Upper Halls, where the singing does not really stop, and
// teaches exactly one thing: a song that is only ever sung by the one who made
// it dies with them. Only a Bard (GetLevelByClass(CLASS_TYPE_BARD, oPC) >= 1)
// is taken as a student; other folk get a seat by the fire and the third verse.
//
// The arc, one bounded first chunk. The greater disciplines of the line -- the
// naming-songs, the lament that stops a fight, the making of a true name -- are
// LATER content, NOT built here; Lindir only names them:
//   * Node 1 (L1):  Learn the opening phrase of the Lay of the Second Spring.
//                   Reward: the Chorister's Torc (q_bard_torc), a modest
//                   +1 CHA, Bard-only amulet.
//   * Node 2 (L8):  Lindir hands over the Unfinished Lay (q_bard_lay) -- a leaf
//                   of vellum that breaks off mid-line -- to be carried until an
//                   ending happens to the bearer.
//   * Node 3 (L15): The missing line is spoken; Lindir has the finished Lay cut
//                   into the Rapier of the Deathless Song (q_bard_rap), a +2
//                   Bard-only rapier. Line I done, the greater forms named for a
//                   later day.
//
// LEVEL GATES ARE BARD CLASS LEVELS, not total hit dice: every node uses
// GetLevelByClass(CLASS_TYPE_BARD, oPC), so a multiclass cannot buy the line's
// rewards with levels taken elsewhere. (Matches the tightened paladin and monk
// lines, not the older GetHitDice ones.)
//
// Rewards are deliberately bard-legal: an amulet and a rapier, both weapons and
// gear a Bard is proficient with, so nothing on the line sits unusable in the
// pack. Use Limitation: Class Bard is iprp_classes row 1, verified against
// cloakofthebard.uti.json rather than guessed, and consistent with the confirmed
// Cleric 2 / Druid 3 / Monk 5 / Paladin 6 / Ranger 7 rows.
//
// Persistence: campaign DB "bardlinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the monk line).
//   Key "song_stage": 0 none / 1 taught / 2 lay carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Lindir is script-spawned at the admin-placed waypoint AP_bardlineearly_1
// (Rivendell Upper Halls, rivendellupperha) by q_bard_spawn, fired from the area
// OnEnter wrapper q_bard_enter. Everything no-ops gracefully until the waypoint
// exists (see the roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string BRD_DB       = "bardlinedb";      // shared campaign DB
const string BRD_STAGEKEY = "song_stage";      // per-character stage int
const string BRD_QUEST    = "bard_lay";        // journal category tag
const string BRD_MSTR     = "q_bard_mstr";     // giver blueprint + tag
const string BRD_WP_TAG   = "AP_bardlineearly_1"; // admin-placed waypoint

const int BRD_LVL_NODE2 = 8;    // return for the Lay at Bard 8
const int BRD_LVL_NODE3 = 15;   // return to give the ending at Bard 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int BRD_GetStage(object oPC)
{
    return GetCampaignInt(BRD_DB, BRD_STAGEKEY, oPC);
}

void BRD_SetStage(object oPC, int nStage)
{
    SetCampaignInt(BRD_DB, BRD_STAGEKEY, nStage, oPC);
}

// The line's level currency: Bard class levels only.
int BRD_BardLevel(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_BARD, oPC);
}

// TRUE if oPC has at least one level of Bard -- the line's entry gate.
int BRD_IsBard(object oPC)
{
    return BRD_BardLevel(oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: be taken as a student. Bard-gated, one-way (stage 0 -> 1).
void BRD_TakeLesson(object oPC)
{
    if (!BRD_IsBard(oPC)) return;
    if (BRD_GetStage(oPC) != 0) return;

    BRD_SetStage(oPC, 1);
    AddJournalQuestEntry(BRD_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_bard_torc", oPC, 1);   // Chorister's Torc (+1 CHA, Bard)
}

// Node 2: receive the Unfinished Lay (stage 1 -> 2). Level gate is enforced by
// the dialogue StartingConditional; guarded here too against a stale node.
void BRD_TakeLay(object oPC)
{
    if (BRD_GetStage(oPC) != 1) return;
    if (BRD_BardLevel(oPC) < BRD_LVL_NODE2) return;

    BRD_SetStage(oPC, 2);
    AddJournalQuestEntry(BRD_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_bard_lay")))
        CreateItemOnObject("q_bard_lay", oPC, 1);  // The Unfinished Lay (plot)
}

// Node 3: the finished Lay is cut into the Rapier of the Deathless Song
// (stage 2 -> 3). Consumes the vellum if the PC still carries it; the reward is
// given regardless so a lost page cannot brick the line at the last step.
void BRD_TakeEnding(object oPC)
{
    if (BRD_GetStage(oPC) != 2) return;
    if (BRD_BardLevel(oPC) < BRD_LVL_NODE3) return;

    BRD_SetStage(oPC, 3);

    object oLay = GetItemPossessedBy(oPC, "q_bard_lay");
    if (GetIsObjectValid(oLay)) DestroyObject(oLay);

    AddJournalQuestEntry(BRD_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_bard_rap", oPC, 1);  // Rapier of the Deathless Song
}

// ------------------------------------------------------------
// Spawn Lindir at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void BRD_SpawnMaster()
{
    if (GetIsObjectValid(GetObjectByTag(BRD_MSTR))) return;

    object oWP = GetWaypointByTag(BRD_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, BRD_MSTR, GetLocation(oWP));
}
