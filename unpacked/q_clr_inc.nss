// q_clr_inc.nss -- "The Flame of Anor", Cleric class-line I (roadmap: cleric-line-early)
//
// The early nodes (L1 / L8 / L15) of the Cleric line. Aldamir, Keeper of the
// Flame (q_clr_keep), tends the Secret Fire in the Temple of Illuvatar. He
// watches for those who carry the true calling and would learn to bear the
// Flame of Anor -- the sacred fire the faithful set against the Shadow. Only a
// Cleric (GetLevelByClass(CLASS_TYPE_CLERIC) >= 1) is offered the calling;
// other folk get a courteous blessing and nothing more.
//
// The arc, one bounded first chunk. The greater consecrations of the Flame --
// Narya's aura and the endgame gifts -- are LATER content, NOT built here;
// Aldamir only foreshadows them:
//   * Node 1 (L1):  Take up the tending of the Secret Fire. Reward: the
//                   Acolyte's Censer-Amulet (q_clr_amul), a modest +1 WIS,
//                   Cleric-only amulet.
//   * Node 2 (L8):  Aldamir entrusts the Reliquary of the Kindled Ember
//                   (q_clr_ember) -- a warded relic of the Secret Fire -- and
//                   sends the PC out to keep its flame and grow in faith.
//   * Node 3 (L15): Grown in devotion, the PC brings the reliquary back;
//                   Aldamir kindles its ember into the Mace of the Kindled
//                   Flame (q_clr_mace), a +2 Cleric-only mace touched with WIS.
//                   Line I done, and the greater Flame named for a later day.
//
// Persistence: campaign DB "clrlinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the wizard line).
//   Key "flame_stage": 0 none / 1 tending / 2 reliquary carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Aldamir is script-spawned at the admin-placed waypoint AP_clericlineearly_1
// (Temple of Illuvatar, templeofilluvata) by q_clr_spawn, fired from the area
// OnEnter wrapper q_clr_enter. Everything no-ops gracefully until the waypoint
// exists (see the roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string CLR_DB       = "clrlinedb";      // shared campaign DB
const string CLR_STAGEKEY = "flame_stage";    // per-character stage int
const string CLR_QUEST    = "clr_anor";       // journal category tag
const string CLR_KEEP     = "q_clr_keep";     // giver blueprint + tag
const string CLR_WP_TAG   = "AP_clericlineearly_1"; // admin-placed waypoint

const int CLR_LVL_NODE2 = 8;    // return for the reliquary at level 8
const int CLR_LVL_NODE3 = 15;   // return to kindle the mace at level 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int CLR_GetStage(object oPC)
{
    return GetCampaignInt(CLR_DB, CLR_STAGEKEY, oPC);
}

void CLR_SetStage(object oPC, int nStage)
{
    SetCampaignInt(CLR_DB, CLR_STAGEKEY, nStage, oPC);
}

// TRUE if oPC has at least one level of Cleric -- the line's entry gate.
int CLR_IsCleric(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_CLERIC, oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: take up the tending. Cleric-gated, one-way (stage 0 -> 1).
void CLR_TakeCalling(object oPC)
{
    if (!CLR_IsCleric(oPC)) return;
    if (CLR_GetStage(oPC) != 0) return;

    CLR_SetStage(oPC, 1);
    AddJournalQuestEntry(CLR_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_clr_amul", oPC, 1);   // Acolyte's Censer-Amulet (+1 WIS, Cleric)
}

// Node 2: receive the Reliquary of the Kindled Ember (stage 1 -> 2). Level gate
// is enforced by the dialogue StartingConditional; guarded here too against a
// stale node.
void CLR_TakeReliquary(object oPC)
{
    if (CLR_GetStage(oPC) != 1) return;
    if (GetHitDice(oPC) < CLR_LVL_NODE2) return;

    CLR_SetStage(oPC, 2);
    AddJournalQuestEntry(CLR_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_clr_ember")))
        CreateItemOnObject("q_clr_ember", oPC, 1);  // Reliquary of the Kindled Ember (plot)
}

// Node 3: kindle the ember into the Mace of the Kindled Flame (stage 2 -> 3).
// Consumes the reliquary if the PC still carries it; the reward is given
// regardless so a lost reliquary cannot brick the line at the last step.
void CLR_TakeReturn(object oPC)
{
    if (CLR_GetStage(oPC) != 2) return;
    if (GetHitDice(oPC) < CLR_LVL_NODE3) return;

    CLR_SetStage(oPC, 3);

    object oRel = GetItemPossessedBy(oPC, "q_clr_ember");
    if (GetIsObjectValid(oRel)) DestroyObject(oRel);

    AddJournalQuestEntry(CLR_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_clr_mace", oPC, 1);  // Mace of the Kindled Flame (+2, Cleric)
}

// ------------------------------------------------------------
// Spawn Aldamir at the admin-placed waypoint. Graceful no-op until the
// waypoint exists; never double-spawns (module-wide tag guard).
void CLR_SpawnKeeper()
{
    if (GetIsObjectValid(GetObjectByTag(CLR_KEEP))) return;

    object oWP = GetWaypointByTag(CLR_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, CLR_KEEP, GetLocation(oWP));
}
