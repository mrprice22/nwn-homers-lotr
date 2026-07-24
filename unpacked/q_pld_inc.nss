// q_pld_inc.nss -- "Oathsworn to the West", Paladin class-line I (roadmap: paladin-line-early)
//
// The early nodes (L1 / L8 / L15) of the Paladin line. Hallas the Oathkeeper,
// an old knight of the Citadel, keeps the Keep of Minas Tirith. He has outlived
// most of the men he swore beside, and takes the oath of the West from those
// who come to it young -- not for Gondor's sake, he says, but so that there is
// one more person in the world who has said the thing out loud in front of a
// witness. Only a Paladin (GetLevelByClass(CLASS_TYPE_PALADIN, oPC) >= 1) is
// offered the oath; other folk get a courteous word about the wall, and nothing
// more.
//
// The arc, one bounded first chunk. The greater deeds of the line -- the ride
// to the Pelennor, the breaking of the Black Gate, the Witch-king's ending --
// are LATER content, NOT built here; Hallas only foreshadows them:
//   * Node 1 (L1):  Swear the oath of the West. Reward: the Token of the White
//                   Tree (q_pld_amul), a modest +1 CHA, Paladin-only amulet.
//   * Node 2 (L8):  Hallas sets the oath down and seals it -- the Sealed Oath
//                   of Fealty (q_pld_seal) -- and sends the PC out to carry it
//                   until it is true rather than merely said.
//   * Node 3 (L15): Grown into the oath, the PC brings the seal back unbroken;
//                   Hallas has it closed into the pommel of the Sword of the
//                   Oathsworn (q_pld_swrd), a +2 Paladin-only long sword.
//                   Line I done, the greater charges named for a later day.
//
// LEVEL GATES ARE PALADIN CLASS LEVELS, not total hit dice: every node uses
// GetLevelByClass(CLASS_TYPE_PALADIN, oPC), so a multiclass cannot buy the
// line's rewards with levels taken elsewhere.
//
// Persistence: campaign DB "pldlinedb", per-character (oPC-keyed
// Get/SetCampaignInt -- relog- and restart-safe, mirrors the druid line).
//   Key "oath_stage": 0 none / 1 sworn / 2 seal carried / 3 line done.
// One-off: the stage only advances, so rewards are never farmable.
//
// Hallas is script-spawned at the admin-placed waypoint AP_paladinlineearly_1
// (Minas Tirith: Keep, area005) by q_pld_spawn, fired from the area OnEnter
// wrapper q_pld_enter. Everything no-ops gracefully until the waypoint exists
// (see the roadmap item manual_steps) and never double-spawns.
// Swearing the oath also commits the character to the Good (Free Peoples)
// faction and locks them out of the Evil light-shaft (Faction_SetOath), matching
// the Blackguard's Black Oath on the other side.
#include "faction_db"

const string PLD_DB       = "pldlinedb";      // shared campaign DB
const string PLD_STAGEKEY = "oath_stage";     // per-character stage int
const string PLD_QUEST    = "pld_oath";       // journal category tag
const string PLD_KEEP     = "q_pld_keep";     // giver blueprint + tag
const string PLD_WP_TAG   = "AP_paladinlineearly_1"; // admin-placed waypoint

const int PLD_LVL_NODE2 = 8;    // return to seal the oath at Paladin 8
const int PLD_LVL_NODE3 = 15;   // return to be given the sword at Paladin 15

// ------------------------------------------------------------
// Stage accessors (persistent, per character).

int PLD_GetStage(object oPC)
{
    return GetCampaignInt(PLD_DB, PLD_STAGEKEY, oPC);
}

void PLD_SetStage(object oPC, int nStage)
{
    SetCampaignInt(PLD_DB, PLD_STAGEKEY, nStage, oPC);
}

// The line's level currency: Paladin class levels only.
int PLD_PalLevel(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_PALADIN, oPC);
}

// TRUE if oPC has at least one level of Paladin -- the line's entry gate.
int PLD_IsPaladin(object oPC)
{
    return PLD_PalLevel(oPC) >= 1;
}

// ------------------------------------------------------------
// Node action handlers (called from the conversation reply Scripts, so the
// reward fires the instant the reply is chosen -- escape-closing the following
// line cannot dodge a stage advance or a handed-out prize).

// Node 1: swear the oath of the West. Paladin-gated, one-way (stage 0 -> 1).
void PLD_TakeOath(object oPC)
{
    if (!PLD_IsPaladin(oPC)) return;
    if (PLD_GetStage(oPC) != 0) return;

    PLD_SetStage(oPC, 1);
    AddJournalQuestEntry(PLD_QUEST, 1, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_pld_amul", oPC, 1);   // Token of the White Tree (+1 CHA, Paladin)
    Faction_SetOath(oPC, "Good");   // optional oath: commit to the West, lock the dark road
}

// Node 2: receive the Sealed Oath of Fealty (stage 1 -> 2). Level gate is
// enforced by the dialogue StartingConditional; guarded here too against a
// stale node.
void PLD_TakeSeal(object oPC)
{
    if (PLD_GetStage(oPC) != 1) return;
    if (PLD_PalLevel(oPC) < PLD_LVL_NODE2) return;

    PLD_SetStage(oPC, 2);
    AddJournalQuestEntry(PLD_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_pld_seal")))
        CreateItemOnObject("q_pld_seal", oPC, 1);  // Sealed Oath of Fealty (plot)
}

// Node 3: the seal is closed into the Sword of the Oathsworn (stage 2 -> 3).
// Consumes the seal if the PC still carries it; the reward is given regardless
// so a lost seal cannot brick the line at the last step.
void PLD_TakeReturn(object oPC)
{
    if (PLD_GetStage(oPC) != 2) return;
    if (PLD_PalLevel(oPC) < PLD_LVL_NODE3) return;

    PLD_SetStage(oPC, 3);

    object oSeal = GetItemPossessedBy(oPC, "q_pld_seal");
    if (GetIsObjectValid(oSeal)) DestroyObject(oSeal);

    AddJournalQuestEntry(PLD_QUEST, 3, oPC, FALSE, FALSE, TRUE);
    CreateItemOnObject("q_pld_swrd", oPC, 1);  // Sword of the Oathsworn (+2, Paladin)
}

// ------------------------------------------------------------
// Spawn Hallas at the admin-placed waypoint. Graceful no-op until the waypoint
// exists; never double-spawns (module-wide tag guard).
void PLD_SpawnKeeper()
{
    if (GetIsObjectValid(GetObjectByTag(PLD_KEEP))) return;

    object oWP = GetWaypointByTag(PLD_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, PLD_KEEP, GetLocation(oWP));
}
