// q_mnk_inc.nss -- "The Empty Hand", Monk class-line I (roadmap: monk-line-early)
//
// The early nodes (L1 / L8 / L15) of the Monk line. Orovan the Windless keeps
// the bare summit of Emyn Arnen, above the last of the trees, where the wind
// comes off Anduin and there is nothing at all to hold on to. He came west a
// long time ago out of the far East and stopped walking here. He teaches only
// one thing, and only to those already on that road: that a hand which is
// holding something cannot be used for anything else. Only a Monk
// (GetLevelByClass(CLASS_TYPE_MONK, oPC) >= 1) is taken as a student; other
// folk get a cup of cold water and a civil silence.
//
// The arc, one bounded first chunk. The greater disciplines of the line -- the
// unbreathing form, the still point, the open palm that stops a blade -- are
// LATER content, NOT built here; Orovan only names them:
//   * Node 1 (L1):  Set down what you are carrying. Reward: the Cord of the
//                   Empty Hand (q_mnk_cord), a modest +1 WIS, Monk-only amulet.
//   * Node 2 (L8):  Orovan gives the Unspoken Stone (q_mnk_stne) -- a river
//                   pebble with nothing written on it -- to be carried until
//                   the student stops noticing it.
//   * Node 3 (L15): The stone comes back unremarked upon; Orovan sets it into
//                   the haft of the Kama of the Windless Peak (q_mnk_kama), a
//                   +2 Monk-only kama. Line I done, the greater forms named for
//                   a later day.
//
// LEVEL GATES ARE MONK CLASS LEVELS, not total hit dice: every node uses
// GetLevelByClass(CLASS_TYPE_MONK, oPC), so a multiclass cannot buy the line's
// rewards with levels taken elsewhere.
//
// Rewards are deliberately monk-legal: an amulet and a kama. Nothing in this
// line hands out armour, a shield, or a weapon that would break the monk's AC
// bonus or flurry of blows.
//
// Persistence: campaign DB "mnklinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the paladin line).
//   Key "hand_stage": 0 none / 1 taught / 2 stone carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Orovan is script-spawned at the admin-placed waypoint AP_monklineearly_1
// (Emyn Arnen: Peak, emynarnen) by q_mnk_spawn, fired from the area OnEnter
// wrapper q_mnk_enter. Everything no-ops gracefully until the waypoint exists
// (see the roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string MNK_DB       = "mnklinedb";      // shared campaign DB
const string MNK_STAGEKEY = "hand_stage";     // per-character stage int
const string MNK_QUEST    = "mnk_hand";       // journal category tag
const string MNK_MSTR     = "q_mnk_mstr";     // giver blueprint + tag
const string MNK_WP_TAG   = "AP_monklineearly_1"; // admin-placed waypoint

const int MNK_LVL_NODE2 = 8;    // return for the stone at Monk 8
const int MNK_LVL_NODE3 = 15;   // return to be given the kama at Monk 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int MNK_GetStage(object oPC)
{
    return GetCampaignInt(MNK_DB, MNK_STAGEKEY, oPC);
}

void MNK_SetStage(object oPC, int nStage)
{
    SetCampaignInt(MNK_DB, MNK_STAGEKEY, nStage, oPC);
}

// The line's level currency: Monk class levels only.
int MNK_MonkLevel(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_MONK, oPC);
}

// TRUE if oPC has at least one level of Monk -- the line's entry gate.
int MNK_IsMonk(object oPC)
{
    return MNK_MonkLevel(oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: be taken as a student. Monk-gated, one-way (stage 0 -> 1).
void MNK_TakeLesson(object oPC)
{
    if (!MNK_IsMonk(oPC)) return;
    if (MNK_GetStage(oPC) != 0) return;

    MNK_SetStage(oPC, 1);
    AddJournalQuestEntry(MNK_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_mnk_cord", oPC, 1);   // Cord of the Empty Hand (+1 WIS, Monk)
}

// Node 2: receive the Unspoken Stone (stage 1 -> 2). Level gate is enforced by
// the dialogue StartingConditional; guarded here too against a stale node.
void MNK_TakeStone(object oPC)
{
    if (MNK_GetStage(oPC) != 1) return;
    if (MNK_MonkLevel(oPC) < MNK_LVL_NODE2) return;

    MNK_SetStage(oPC, 2);
    AddJournalQuestEntry(MNK_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_mnk_stne")))
        CreateItemOnObject("q_mnk_stne", oPC, 1);  // Unspoken Stone (plot)
}

// Node 3: the stone is set into the Kama of the Windless Peak (stage 2 -> 3).
// Consumes the stone if the PC still carries it; the reward is given regardless
// so a lost stone cannot brick the line at the last step.
void MNK_TakeReturn(object oPC)
{
    if (MNK_GetStage(oPC) != 2) return;
    if (MNK_MonkLevel(oPC) < MNK_LVL_NODE3) return;

    MNK_SetStage(oPC, 3);

    object oStone = GetItemPossessedBy(oPC, "q_mnk_stne");
    if (GetIsObjectValid(oStone)) DestroyObject(oStone);

    AddJournalQuestEntry(MNK_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_mnk_kama", oPC, 1);  // Kama of the Windless Peak (+2, Monk)
}

// ------------------------------------------------------------
// Spawn Orovan at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void MNK_SpawnMaster()
{
    if (GetIsObjectValid(GetObjectByTag(MNK_MSTR))) return;

    object oWP = GetWaypointByTag(MNK_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, MNK_MSTR, GetLocation(oWP));
}
