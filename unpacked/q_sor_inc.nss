// q_sor_inc.nss -- "Blood of Elder Days", Sorcerer class-line I
// (roadmap: sorcerer-line-early)
//
// PREFIX NOTE: this line uses q_sor_*. The prefix was checked and is free --
// nothing in unpacked/ begins q_sor_ or q_src_, and the only pre-existing
// "sorcerer" names are unrelated content blueprints (darksorcerer.utc,
// gwathsorcerer.utc, orcsorcerer001.utc, beltofsorcerery.uti,
// darksorcererrobe.uti, carnsorcq.dlg) -- none of which share the q_sor_ stem,
// so grep stays unambiguous. No pre-existing half-built Sorcerer-line work was
// found. Every q_sor_* resref stays inside the 16-character limit.
//
// The early nodes (L1 / L8 / L15) of the Sorcerer line. Erendis of the Drowned
// House keeps a fire among the Ruins of Annuminas, where the old Numenorean
// halls are going quietly back into the lake. She is not a teacher of spells --
// she says plainly that nobody taught her either -- and what she offers is the
// only thing she thinks can be handed on: how to stop fighting the blood that
// woke in you without asking. Only a Sorcerer
// (GetLevelByClass(CLASS_TYPE_SORCERER, oPC) >= 1) is taken up; other folk get
// a share of the fire and an old story about the drowning of Numenor.
//
// The arc, one bounded first chunk. The greater matter of the line -- the
// dragon-speech, the sceptre, the unbinding of the elder blood -- is LATER
// content, NOT built here; Erendis only names it:
//   * Node 1 (L1):  She names what you are and gives you the Signet of the
//                   Drowned House (q_sor_sig), a modest +1 CHA Sorcerer-only
//                   ring.
//   * Node 2 (L8):  She hands over the Shard of Sea-Glass (q_sor_glas) -- a
//                   worn scrap of the drowned country -- to be carried until
//                   the blood has cost you something.
//   * Node 3 (L15): You tell her what it cost. The shard is set into the head
//                   of the Staff of Elder Days (q_sor_stff), a +2 Sorcerer-only
//                   quarterstaff. Line I done, the greater work named for later.
//
// LEVEL GATES ARE SORCERER CLASS LEVELS, not total hit dice: every node uses
// GetLevelByClass(CLASS_TYPE_SORCERER, oPC), so a multiclass cannot buy the
// line's rewards with levels taken elsewhere. (Matches the tightened paladin,
// monk and bard lines, not the older GetHitDice ones.)
//
// Rewards are deliberately sorcerer-legal: a ring and a quarterstaff, both
// inside Sorcerer proficiency, so nothing on the line sits unusable in the pack.
// Use Limitation: Class Sorcerer is iprp_classes row 9, verified against the
// module's own arcane-restricted items (sarumansrobes, item053 "Gandalf's
// Staff", ashmlw006 "Shield of the Mage" -- each carrying the 9/10
// Sorcerer+Wizard pair) rather than guessed, and consistent with the confirmed
// Bard 1 / Cleric 2 / Druid 3 / Monk 5 / Paladin 6 / Ranger 7 rows.
//
// Persistence: campaign DB "sorclinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the bard line).
//   Key "blood_stage": 0 none / 1 named / 2 shard carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Erendis is script-spawned at the admin-placed waypoint AP_sorcererlineearly_1
// (Ruins of Annuminas, ruinsofannuminas) by q_sor_spawn, fired from the area
// OnEnter wrapper q_sor_enter. Everything no-ops gracefully until the waypoint
// exists (see the roadmap item manual_steps) and never double-spawns.
// All engine calls used here are base NWScript builtins -- no framework include.

const string SOR_DB       = "sorclinedb";       // shared campaign DB
const string SOR_STAGEKEY = "blood_stage";      // per-character stage int
const string SOR_QUEST    = "sor_blood";        // journal category tag
const string SOR_MSTR     = "q_sor_mstr";       // giver blueprint + tag
const string SOR_WP_TAG   = "AP_sorcererlineearly_1"; // admin-placed waypoint

const int SOR_LVL_NODE2 = 8;    // return for the shard at Sorcerer 8
const int SOR_LVL_NODE3 = 15;   // return to tell the cost at Sorcerer 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int SOR_GetStage(object oPC)
{
    return GetCampaignInt(SOR_DB, SOR_STAGEKEY, oPC);
}

void SOR_SetStage(object oPC, int nStage)
{
    SetCampaignInt(SOR_DB, SOR_STAGEKEY, nStage, oPC);
}

// The line's level currency: Sorcerer class levels only.
int SOR_SorcLevel(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_SORCERER, oPC);
}

// TRUE if oPC has at least one level of Sorcerer -- the line's entry gate.
int SOR_IsSorc(object oPC)
{
    return SOR_SorcLevel(oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: be named. Sorcerer-gated, one-way (stage 0 -> 1).
void SOR_TakeNaming(object oPC)
{
    if (!SOR_IsSorc(oPC)) return;
    if (SOR_GetStage(oPC) != 0) return;

    SOR_SetStage(oPC, 1);
    AddJournalQuestEntry(SOR_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_sor_sig", oPC, 1);   // Signet of the Drowned House
}

// Node 2: receive the Shard of Sea-Glass (stage 1 -> 2). Level gate is enforced
// by the dialogue StartingConditional; guarded here too against a stale node.
void SOR_TakeShard(object oPC)
{
    if (SOR_GetStage(oPC) != 1) return;
    if (SOR_SorcLevel(oPC) < SOR_LVL_NODE2) return;

    SOR_SetStage(oPC, 2);
    AddJournalQuestEntry(SOR_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_sor_glas")))
        CreateItemOnObject("q_sor_glas", oPC, 1);  // Shard of Sea-Glass (plot)
}

// Node 3: the shard is set into the Staff of Elder Days (stage 2 -> 3).
// Consumes the shard if the PC still carries it; the reward is given regardless
// so a lost shard cannot brick the line at the last step.
void SOR_TakeCost(object oPC)
{
    if (SOR_GetStage(oPC) != 2) return;
    if (SOR_SorcLevel(oPC) < SOR_LVL_NODE3) return;

    SOR_SetStage(oPC, 3);

    object oShard = GetItemPossessedBy(oPC, "q_sor_glas");
    if (GetIsObjectValid(oShard)) DestroyObject(oShard);

    AddJournalQuestEntry(SOR_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_sor_stff", oPC, 1);  // Staff of Elder Days
}

// ------------------------------------------------------------
// Spawn Erendis at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void SOR_SpawnMaster()
{
    if (GetIsObjectValid(GetObjectByTag(SOR_MSTR))) return;

    object oWP = GetWaypointByTag(SOR_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, SOR_MSTR, GetLocation(oWP));
}
