// q_ftr_inc.nss -- "The Unbroken Shield", Fighter class-line I (roadmap: fighter-line-early)
//
// The early nodes (L1 / L8 / L15) of the Fighter line. Hallas the Shieldwarden
// (q_ftr_hallas), a grey veteran of Gondor's wars, keeps a corner of the
// Prancing Pony common room and takes the measure of any who carry a soldier's
// trade. Only a Fighter (GetLevelByClass(CLASS_TYPE_FIGHTER) >= 1) is offered
// the oath; other folk get a soldier's nod and nothing more.
//
// The arc, one bounded first chunk (the finale -- the Aeglos Reborn spear and
// the Osgiliath wave-defence -- is LATER-tier content, not built here):
//   * Node 1 (L1):  Take the oath of the Unbroken Shield. Reward: the Warden's
//                   Buckler (q_ftr_buckl), a modest +1 Fighter-only shield.
//   * Node 2 (L8):  Hallas tells of a captain who fell at the fords and left a
//                   notched, broken blade. He entrusts the shard (q_ftr_shard)
//                   to the PC to be carried until it can be made whole.
//   * Node 3 (L15): Grown in war, the PC brings the shard back; Hallas has a
//                   smith reforge it into the Warden's Reforged Blade
//                   (q_ftr_blade), a +2 Fighter-only longsword. Line I done.
//
// Persistence: campaign DB "fighterlinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the prestige idiom).
//   Key "ubshield_stage": 0 none / 1 oath taken / 2 shard carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Hallas is script-spawned at the admin-placed waypoint AP_fighterlineearly_1
// (Prancing Pony ground floor, theprancingpo001) by q_ftr_spawn, fired from the
// area OnEnter wrapper q_ftr_enter. Everything no-ops gracefully until the
// waypoint exists (see the roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string FTR_DB       = "fighterlinedb";   // shared campaign DB
const string FTR_STAGEKEY = "ubshield_stage";  // per-character stage int
const string FTR_QUEST    = "ftr_shield";       // journal category tag
const string FTR_HALLAS   = "q_ftr_hallas";    // giver blueprint + tag
const string FTR_WP_TAG   = "AP_fighterlineearly_1"; // admin-placed waypoint

const int FTR_LVL_NODE2 = 8;    // return for the shard at level 8
const int FTR_LVL_NODE3 = 15;   // return to reforge at level 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int FTR_GetStage(object oPC)
{
    return GetCampaignInt(FTR_DB, FTR_STAGEKEY, oPC);
}

void FTR_SetStage(object oPC, int nStage)
{
    SetCampaignInt(FTR_DB, FTR_STAGEKEY, nStage, oPC);
}

// TRUE if oPC has at least one level of Fighter -- the line's entry gate.
int FTR_IsFighter(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_FIGHTER, oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: seal the oath. Fighter-gated, one-way (stage 0 -> 1).
void FTR_TakeOath(object oPC)
{
    if (!FTR_IsFighter(oPC)) return;
    if (FTR_GetStage(oPC) != 0) return;

    FTR_SetStage(oPC, 1);
    AddJournalQuestEntry(FTR_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_ftr_buckl", oPC, 1);   // Warden's Buckler (+1, Fighter)
}

// Node 2: receive the broken shard (stage 1 -> 2). Level gate is enforced by
// the dialogue StartingConditional; guarded here too against a stale node.
void FTR_TakeShard(object oPC)
{
    if (FTR_GetStage(oPC) != 1) return;
    if (GetHitDice(oPC) < FTR_LVL_NODE2) return;

    FTR_SetStage(oPC, 2);
    AddJournalQuestEntry(FTR_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_ftr_shard")))
        CreateItemOnObject("q_ftr_shard", oPC, 1);  // notched captain's shard (plot)
}

// Node 3: reforge the shard into the Warden's Reforged Blade (stage 2 -> 3).
// Consumes the shard if the PC still carries it; the reward is given regardless
// so a lost shard cannot brick the line at the last step.
void FTR_Reforge(object oPC)
{
    if (FTR_GetStage(oPC) != 2) return;
    if (GetHitDice(oPC) < FTR_LVL_NODE3) return;

    FTR_SetStage(oPC, 3);

    object oShard = GetItemPossessedBy(oPC, "q_ftr_shard");
    if (GetIsObjectValid(oShard)) DestroyObject(oShard);

    AddJournalQuestEntry(FTR_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_ftr_blade", oPC, 1);   // Warden's Reforged Blade (+2, Fighter)
}

// ------------------------------------------------------------
// Spawn Hallas at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void FTR_SpawnHallas()
{
    if (GetIsObjectValid(GetObjectByTag(FTR_HALLAS))) return;

    object oWP = GetWaypointByTag(FTR_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, FTR_HALLAS, GetLocation(oWP));
}
