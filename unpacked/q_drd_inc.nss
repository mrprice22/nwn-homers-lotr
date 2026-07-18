// q_drd_inc.nss -- "The Breathing of the World", Druid class-line I (roadmap: druid-line-early)
//
// The early nodes (L1 / L8 / L15) of the Druid line. Naldor the Green, an old
// Woodman-hermit and a pupil of Radagast, keeps the wood at Rhosgobel. He
// listens for the slow breathing of the world -- the turning of leaf and root
// and beast that the wise call the Green Listening -- and takes up only those
// who already hear a little of it. Only a Druid
// (GetLevelByClass(CLASS_TYPE_DRUID, oPC) >= 1) is offered the listening;
// other folk get a courteous word about the wood, and nothing more.
//
// The arc, one bounded first chunk. The greater deeds of the line -- the
// Entmoot, the waking of the Old Forest, the wrath of the wild against Isengard
// -- are LATER content, NOT built here; Naldor only foreshadows them:
//   * Node 1 (L1):  Take up the Green Listening. Reward: the Amulet of the Green
//                   Listening (q_drd_amul), a modest +1 WIS, Druid-only amulet.
//   * Node 2 (L8):  Naldor entrusts the Seed of the Elder Wood (q_drd_seed) --
//                   a seed of a tree older than the Shire -- and sends the PC
//                   out to carry it through the wild lands and grow into it.
//   * Node 3 (L15): Grown in the craft, the PC brings the seed back; Naldor has
//                   it grown around a shaft of mallorn into the Staff of the
//                   Breathing World (q_drd_staf), a +2 Druid-only quarterstaff.
//                   Line I done, the greater wakings named for a later day.
//
// Persistence: campaign DB "drdlinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the ranger line).
//   Key "breath_stage": 0 none / 1 listening / 2 seed carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Naldor is script-spawned at the admin-placed waypoint AP_druidlineearly_1
// (Rhosgobel, rhosgobel) by q_drd_spawn, fired from the area OnEnter wrapper
// q_drd_enter. Everything no-ops gracefully until the waypoint exists (see the
// roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string DRD_DB       = "drdlinedb";      // shared campaign DB
const string DRD_STAGEKEY = "breath_stage";   // per-character stage int
const string DRD_QUEST    = "drd_breath";     // journal category tag
const string DRD_KEEP     = "q_drd_keep";     // giver blueprint + tag
const string DRD_WP_TAG   = "AP_druidlineearly_1"; // admin-placed waypoint

const int DRD_LVL_NODE2 = 8;    // return for the seed at level 8
const int DRD_LVL_NODE3 = 15;   // return to grow the staff at level 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int DRD_GetStage(object oPC)
{
    return GetCampaignInt(DRD_DB, DRD_STAGEKEY, oPC);
}

void DRD_SetStage(object oPC, int nStage)
{
    SetCampaignInt(DRD_DB, DRD_STAGEKEY, nStage, oPC);
}

// TRUE if oPC has at least one level of Druid -- the line's entry gate.
int DRD_IsDruid(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_DRUID, oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: take up the Green Listening. Druid-gated, one-way (stage 0 -> 1).
void DRD_TakeListening(object oPC)
{
    if (!DRD_IsDruid(oPC)) return;
    if (DRD_GetStage(oPC) != 0) return;

    DRD_SetStage(oPC, 1);
    AddJournalQuestEntry(DRD_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_drd_amul", oPC, 1);   // Amulet of the Green Listening (+1 WIS, Druid)
}

// Node 2: receive the Seed of the Elder Wood (stage 1 -> 2). Level gate is
// enforced by the dialogue StartingConditional; guarded here too against a
// stale node.
void DRD_TakeSeed(object oPC)
{
    if (DRD_GetStage(oPC) != 1) return;
    if (GetHitDice(oPC) < DRD_LVL_NODE2) return;

    DRD_SetStage(oPC, 2);
    AddJournalQuestEntry(DRD_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_drd_seed")))
        CreateItemOnObject("q_drd_seed", oPC, 1);  // Seed of the Elder Wood (plot)
}

// Node 3: grow the seed into the Staff of the Breathing World (stage 2 -> 3).
// Consumes the seed if the PC still carries it; the reward is given regardless
// so a lost seed cannot brick the line at the last step.
void DRD_TakeReturn(object oPC)
{
    if (DRD_GetStage(oPC) != 2) return;
    if (GetHitDice(oPC) < DRD_LVL_NODE3) return;

    DRD_SetStage(oPC, 3);

    object oSeed = GetItemPossessedBy(oPC, "q_drd_seed");
    if (GetIsObjectValid(oSeed)) DestroyObject(oSeed);

    AddJournalQuestEntry(DRD_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_drd_staf", oPC, 1);  // Staff of the Breathing World (+2, Druid)
}

// ------------------------------------------------------------
// Spawn Naldor at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void DRD_SpawnKeeper()
{
    if (GetIsObjectValid(GetObjectByTag(DRD_KEEP))) return;

    object oWP = GetWaypointByTag(DRD_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, DRD_KEEP, GetLocation(oWP));
}
