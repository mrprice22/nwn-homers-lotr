// q_rng_inc.nss -- "The Uncrowned Path", Ranger class-line I (roadmap: ranger-line-early)
//
// The early nodes (L1 / L8 / L15) of the Ranger line. Halbarad, a warden of the
// Grey Company, keeps a lonely vigil at the Ranger waystation. He watches for
// those with the wandering heart -- folk who would walk the uncrowned path, the
// grey road of the Rangers of the North, who guard the free lands unthanked and
// unrewarded while the world sleeps easy. Only a Ranger
// (GetLevelByClass(CLASS_TYPE_RANGER, oPC) >= 1) is offered the vigil; other
// folk get a courteous word and a warning of the road, and nothing more.
//
// The arc, one bounded first chunk. The greater deeds of the path -- the
// Elendilmir, the Grey Company mustered, the road to the crown -- are LATER
// content, NOT built here; Halbarad only foreshadows them:
//   * Node 1 (L1):  Take up the grey vigil. Reward: the Brooch of the Grey Watch
//                   (q_rng_broc), a modest +1 DEX, Ranger-only cloak-brooch.
//   * Node 2 (L8):  Halbarad entrusts the Star of the Dunedain (q_rng_star) --
//                   a warden's token of the Grey Company -- and sends the PC out
//                   to keep the watch and grow into the road.
//   * Node 3 (L15): Grown in the craft, the PC brings the star back; Halbarad
//                   has it worked into the Bow of the Uncrowned (q_rng_bow), a +2
//                   Ranger-only longbow. Line I done, the crowned road named for
//                   a later day.
//
// Persistence: campaign DB "rnglinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the cleric line).
//   Key "path_stage": 0 none / 1 watching / 2 star carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Halbarad is script-spawned at the admin-placed waypoint AP_rangerlineearly_1
// (Ranger waystation, rangerwaystation) by q_rng_spawn, fired from the area
// OnEnter wrapper q_rng_enter. Everything no-ops gracefully until the waypoint
// exists (see the roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string RNG_DB       = "rnglinedb";      // shared campaign DB
const string RNG_STAGEKEY = "path_stage";     // per-character stage int
const string RNG_QUEST    = "rng_path";       // journal category tag
const string RNG_KEEP     = "q_rng_keep";     // giver blueprint + tag
const string RNG_WP_TAG   = "AP_rangerlineearly_1"; // admin-placed waypoint

const int RNG_LVL_NODE2 = 8;    // return for the star at level 8
const int RNG_LVL_NODE3 = 15;   // return to work the bow at level 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int RNG_GetStage(object oPC)
{
    return GetCampaignInt(RNG_DB, RNG_STAGEKEY, oPC);
}

void RNG_SetStage(object oPC, int nStage)
{
    SetCampaignInt(RNG_DB, RNG_STAGEKEY, nStage, oPC);
}

// TRUE if oPC has at least one level of Ranger -- the line's entry gate.
int RNG_IsRanger(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_RANGER, oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: take up the grey vigil. Ranger-gated, one-way (stage 0 -> 1).
void RNG_TakeVigil(object oPC)
{
    if (!RNG_IsRanger(oPC)) return;
    if (RNG_GetStage(oPC) != 0) return;

    RNG_SetStage(oPC, 1);
    AddJournalQuestEntry(RNG_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_rng_broc", oPC, 1);   // Brooch of the Grey Watch (+1 DEX, Ranger)
}

// Node 2: receive the Star of the Dunedain (stage 1 -> 2). Level gate is
// enforced by the dialogue StartingConditional; guarded here too against a
// stale node.
void RNG_TakeStar(object oPC)
{
    if (RNG_GetStage(oPC) != 1) return;
    if (GetHitDice(oPC) < RNG_LVL_NODE2) return;

    RNG_SetStage(oPC, 2);
    AddJournalQuestEntry(RNG_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_rng_star")))
        CreateItemOnObject("q_rng_star", oPC, 1);  // Star of the Dunedain (plot)
}

// Node 3: work the star into the Bow of the Uncrowned (stage 2 -> 3). Consumes
// the star if the PC still carries it; the reward is given regardless so a lost
// star cannot brick the line at the last step.
void RNG_TakeReturn(object oPC)
{
    if (RNG_GetStage(oPC) != 2) return;
    if (GetHitDice(oPC) < RNG_LVL_NODE3) return;

    RNG_SetStage(oPC, 3);

    object oStar = GetItemPossessedBy(oPC, "q_rng_star");
    if (GetIsObjectValid(oStar)) DestroyObject(oStar);

    AddJournalQuestEntry(RNG_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_rng_bow", oPC, 1);  // Bow of the Uncrowned (+2, Ranger)
}

// ------------------------------------------------------------
// Spawn Halbarad at the admin-placed waypoint. Graceful no-op until the
// waypoint exists; never double-spawns (module-wide tag guard).
void RNG_SpawnKeeper()
{
    if (GetIsObjectValid(GetObjectByTag(RNG_KEEP))) return;

    object oWP = GetWaypointByTag(RNG_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, RNG_KEEP, GetLocation(oWP));
}
