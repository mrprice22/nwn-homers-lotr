// q_rog_inc.nss -- "The Long Shadow", Rogue class-line I (roadmap: rogue-line-early)
//
// The early nodes (L1 / L8 / L15) of the Rogue line. Fenn the Shade
// (q_rog_fenn), a hooded Bree-lander who watches the Prancing Pony's doorways,
// runs "the Long Shadow" -- a loose net of thieves and watchers who keep tally
// of the Enemy's spies on the roads. He takes the measure of any who move light
// on their feet. Only a Rogue (GetLevelByClass(CLASS_TYPE_ROGUE) >= 1) is
// offered a place in the net; other folk get a wary nod and nothing more.
//
// The arc, one bounded first chunk (the capstone -- Shelob's lair, Cirith Ungol
// and the twin blades -- is LATER-tier content, not built here):
//   * Node 1 (L1):  Swear into the Long Shadow. Reward: the Shadowmantle
//                   (q_rog_cloak), a modest +1 Rogue-only cloak.
//   * Node 2 (L8):  Fenn entrusts a cipher-token (q_rog_token) -- a watchword of
//                   the net -- and sends the PC out to carry it unseen through
//                   the wider world and grow into the trade.
//   * Node 3 (L15): Grown in the craft, the PC brings the token back; Fenn's
//                   fence works its hidden steel core into a blade, the
//                   Nightthorn (q_rog_blade), a +2 Rogue-only short sword.
//                   Line I done.
//
// Persistence: campaign DB "roguelinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the fighter line).
//   Key "shadow_stage": 0 none / 1 sworn / 2 token carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Fenn is script-spawned at the admin-placed waypoint AP_roguelineearly_1
// (Prancing Pony ground floor, theprancingpo001) by q_rog_spawn, fired from the
// area OnEnter wrapper q_rog_enter. Everything no-ops gracefully until the
// waypoint exists (see admin-action-required.md) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string ROG_DB       = "roguelinedb";    // shared campaign DB
const string ROG_STAGEKEY = "shadow_stage";   // per-character stage int
const string ROG_QUEST    = "rog_shadow";     // journal category tag
const string ROG_FENN     = "q_rog_fenn";     // giver blueprint + tag
const string ROG_WP_TAG   = "AP_roguelineearly_1"; // admin-placed waypoint

const int ROG_LVL_NODE2 = 8;    // return for the token at level 8
const int ROG_LVL_NODE3 = 15;   // return to reforge at level 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int ROG_GetStage(object oPC)
{
    return GetCampaignInt(ROG_DB, ROG_STAGEKEY, oPC);
}

void ROG_SetStage(object oPC, int nStage)
{
    SetCampaignInt(ROG_DB, ROG_STAGEKEY, nStage, oPC);
}

// TRUE if oPC has at least one level of Rogue -- the line's entry gate.
int ROG_IsRogue(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_ROGUE, oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: swear into the net. Rogue-gated, one-way (stage 0 -> 1).
void ROG_TakeOath(object oPC)
{
    if (!ROG_IsRogue(oPC)) return;
    if (ROG_GetStage(oPC) != 0) return;

    ROG_SetStage(oPC, 1);
    AddJournalQuestEntry(ROG_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_rog_cloak", oPC, 1);   // Shadowmantle (+1, Rogue)
}

// Node 2: receive the cipher-token (stage 1 -> 2). Level gate is enforced by
// the dialogue StartingConditional; guarded here too against a stale node.
void ROG_TakeToken(object oPC)
{
    if (ROG_GetStage(oPC) != 1) return;
    if (GetHitDice(oPC) < ROG_LVL_NODE2) return;

    ROG_SetStage(oPC, 2);
    AddJournalQuestEntry(ROG_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_rog_token")))
        CreateItemOnObject("q_rog_token", oPC, 1);  // cipher-token (plot)
}

// Node 3: work the token's steel core into the Nightthorn (stage 2 -> 3).
// Consumes the token if the PC still carries it; the reward is given regardless
// so a lost token cannot brick the line at the last step.
void ROG_TakeReturn(object oPC)
{
    if (ROG_GetStage(oPC) != 2) return;
    if (GetHitDice(oPC) < ROG_LVL_NODE3) return;

    ROG_SetStage(oPC, 3);

    object oTok = GetItemPossessedBy(oPC, "q_rog_token");
    if (GetIsObjectValid(oTok)) DestroyObject(oTok);

    AddJournalQuestEntry(ROG_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_rog_blade", oPC, 1);   // Nightthorn (+2, Rogue)
}

// ------------------------------------------------------------
// Spawn Fenn at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void ROG_SpawnFenn()
{
    if (GetIsObjectValid(GetObjectByTag(ROG_FENN))) return;

    object oWP = GetWaypointByTag(ROG_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, ROG_FENN, GetLocation(oWP));
}
