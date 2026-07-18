// q_wiz_inc.nss -- "The Colour of Power", Wizard class-line I (roadmap: wizard-line-early)
//
// The early nodes (L1 / L8 / L15) of the Wizard line. Findegil the Grey
// (q_wiz_find), a grey-robed loremaster of the Istari's craft who keeps a
// quiet study in Bag End, watches for the spark of true wizardry. He takes the
// measure of any who carry the Art. Only a Wizard
// (GetLevelByClass(CLASS_TYPE_WIZARD) >= 1) is offered the lore of the Colour
// of Power; other folk get a courteous word and nothing more.
//
// The arc, one bounded first chunk. The COLOUR CHOICE itself -- White,
// Many-Colours or Brown, and the caster-level capstone -- is L46 ENDGAME
// content (wizard-line-endgame), NOT built here; Findegil only foreshadows it:
//   * Node 1 (L1):  Take up the study of the Colour of Power. Reward: the
//                   Apprentice's Amulet (q_wiz_amul), a modest +1 INT,
//                   Wizard-only amulet.
//   * Node 2 (L8):  Findegil entrusts the Loremaster's Tome (q_wiz_tome) -- a
//                   grey book of the Istari's lore -- and sends the PC out into
//                   the wide world to study it and grow in the Art.
//   * Node 3 (L15): Grown in craft, the PC brings the tome back; Findegil binds
//                   its lore into the Staff of the Grey Study (q_wiz_staff), a
//                   +2 INT-touched Wizard-only staff. Line I done, and the
//                   choice of Colour named for a later, higher day.
//
// Persistence: campaign DB "wizlinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the rogue line).
//   Key "colour_stage": 0 none / 1 studying / 2 tome carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Findegil is script-spawned at the admin-placed waypoint AP_wizardlineearly_1
// (Bag End, bagend001) by q_wiz_spawn, fired from the area OnEnter wrapper
// q_wiz_enter. Everything no-ops gracefully until the waypoint exists (see
// roadmap manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string WIZ_DB       = "wizlinedb";      // shared campaign DB
const string WIZ_STAGEKEY = "colour_stage";   // per-character stage int
const string WIZ_QUEST    = "wiz_colour";     // journal category tag
const string WIZ_FIND     = "q_wiz_find";     // giver blueprint + tag
const string WIZ_WP_TAG   = "AP_wizardlineearly_1"; // admin-placed waypoint

const int WIZ_LVL_NODE2 = 8;    // return for the tome at level 8
const int WIZ_LVL_NODE3 = 15;   // return to bind the staff at level 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int WIZ_GetStage(object oPC)
{
    return GetCampaignInt(WIZ_DB, WIZ_STAGEKEY, oPC);
}

void WIZ_SetStage(object oPC, int nStage)
{
    SetCampaignInt(WIZ_DB, WIZ_STAGEKEY, nStage, oPC);
}

// TRUE if oPC has at least one level of Wizard -- the line's entry gate.
int WIZ_IsWizard(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_WIZARD, oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: take up the study. Wizard-gated, one-way (stage 0 -> 1).
void WIZ_TakeStudy(object oPC)
{
    if (!WIZ_IsWizard(oPC)) return;
    if (WIZ_GetStage(oPC) != 0) return;

    WIZ_SetStage(oPC, 1);
    AddJournalQuestEntry(WIZ_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_wiz_amul", oPC, 1);   // Apprentice's Amulet (+1 INT, Wizard)
}

// Node 2: receive the Loremaster's Tome (stage 1 -> 2). Level gate is enforced
// by the dialogue StartingConditional; guarded here too against a stale node.
void WIZ_TakeTome(object oPC)
{
    if (WIZ_GetStage(oPC) != 1) return;
    if (GetHitDice(oPC) < WIZ_LVL_NODE2) return;

    WIZ_SetStage(oPC, 2);
    AddJournalQuestEntry(WIZ_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_wiz_tome")))
        CreateItemOnObject("q_wiz_tome", oPC, 1);  // Loremaster's Tome (plot)
}

// Node 3: bind the tome's lore into the Staff of the Grey Study (stage 2 -> 3).
// Consumes the tome if the PC still carries it; the reward is given regardless
// so a lost tome cannot brick the line at the last step.
void WIZ_TakeReturn(object oPC)
{
    if (WIZ_GetStage(oPC) != 2) return;
    if (GetHitDice(oPC) < WIZ_LVL_NODE3) return;

    WIZ_SetStage(oPC, 3);

    object oTome = GetItemPossessedBy(oPC, "q_wiz_tome");
    if (GetIsObjectValid(oTome)) DestroyObject(oTome);

    AddJournalQuestEntry(WIZ_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_wiz_staff", oPC, 1);  // Staff of the Grey Study (+2, Wizard)
}

// ------------------------------------------------------------
// Spawn Findegil at the admin-placed waypoint. Graceful no-op until the
// waypoint exists; never double-spawns (module-wide tag guard).
void WIZ_SpawnFindegil()
{
    if (GetIsObjectValid(GetObjectByTag(WIZ_FIND))) return;

    object oWP = GetWaypointByTag(WIZ_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, WIZ_FIND, GetLocation(oWP));
}
