// q_frk_inc.nss -- "The Forbidden Realms" (roadmap: forbidden-realms-key-tier)
//
// The Forbidden Realms Key has always been stealable from Summanus in
// Numenor: Noirinan (falseheaven) but opened nothing. This gives it a door.
//
// The chain:
//   * Acquire the key (Tag "ForbiddenRealmsKey", any route -- pickpocket,
//     loot, trade). acquireditem_tag fires FRK_OnKeyAcquired: journal entry 1.
//     Characters who stole it before this shipped are caught retroactively by
//     FRK_LoginCheck, called from mod_cliententer.
//   * In Noirinan a sealed barrow-gate (placeable q_frk_gate) stands at the
//     admin-placed waypoint AP_forbiddenrealmskeytier_1. Using it without the
//     key does nothing but describe the seal; with the key it opens and jumps
//     the user to AP_forbiddenrealmskeytier_2 -- journal entry 2, then 3.
//   * That waypoint is in gravesofthelostk (Tombs of the Lost Souls), an area
//     with no connections at all today. Its OnEnter wrapper (q_frk_tomb)
//     spawns a return gate at _2 so the tomb is not a one-way trip.
//   * Killing a court member runs q_frk_death, which records the kill; all
//     three down completes the journal (entry 10, End).
//
// Persistence: campaign DB "forbiddendb", per character (oPC-keyed
// Get/SetCampaignInt), mirroring the fighterlinedb / prestige idiom.
//   "frk_stage"  0 none / 1 key acquired / 2 gate opened / 3 tombs entered
//   "frk_king", "frk_queen", "frk_archer"  1 once that court member is killed
//
// WHERE THE COURT ACTUALLY IS (2026-09-04). The barrow-court no longer stands
// in gravesofthelostk. The admin built it for real in the toolset as area028,
// "Weather Top's Hidden Court", reached from Amon Sul (area026) through the
// wtop_hiddencave trigger and past a key-shard puzzle -- see wtop_court.nss,
// wtop_keymake.nss and wtop_kdoor.nss. The King and Queen are PLACED instances
// on their thrones there (so the Roll of the Fallen can see them) and the
// Archer is one of 22 script-spawned Royal Archers.
//
// So FRK_SpawnCourt and the _3/_4/_5 waypoints are gone -- nothing here spawns
// the court any more. What survives is the KILL BOOKKEEPING at the bottom of
// this file: q_frk_death still sits on all three blueprints and still completes
// the journal, which is the half of the quest area028 does not provide for
// itself. Killing the court in area028 therefore finishes "The Forbidden
// Realms" exactly as killing it in the tombs would have.
//
// The Noirinan gate half still no-ops gracefully while
// AP_forbiddenrealmskeytier_1 / _2 are unplaced (they are, and per the roadmap
// item they are SUPERSEDED): no gate spawns and the quest sits at entry 1 until
// the player walks into Amon Sul the ordinary way.
//
// All calls are base NWScript builtins -- no framework include.

const string FRK_DB      = "forbiddendb";
const string FRK_STAGE   = "frk_stage";
const string FRK_QUEST   = "frk_tombs";              // journal category Tag
const string FRK_KEYTAG  = "ForbiddenRealmsKey";     // item Tag on the key

// Admin-placed waypoints (tag = AP_ + roadmap id with hyphens stripped + index)
const string FRK_WP_GATE  = "AP_forbiddenrealmskeytier_1";  // Noirinan, the seal
const string FRK_WP_TOMB  = "AP_forbiddenrealmskeytier_2";  // Tombs, arrival + exit

// The three court members whose deaths this quest counts. These are the
// blueprints that carry q_frk_death; area028 decides where they stand.
//
// The King moved from the CR-454 weathertopkin003 to weathertopkin004 on
// 2026-09-04, per the answered design question ("CR-1514 King sounds more
// appropriate than the 454 king.. Going for a TOUGH boss fight"). Both he and
// the Queen were then rebuilt to out-scale Summanus (CR 2938 / 8000 HP / AC 70).
// The Archer is the court's own Royal Archer rather than the hill's, so the
// quest leg completes on any of the 22 that stand in area028.
const string FRK_RR_KING   = "weathertopkin004";   // Weathertop King,        CR 3400
const string FRK_RR_QUEEN  = "weathertopque003";   // Weathertop Queen,       CR 3100
const string FRK_RR_ARCHER = "wtop_crtarcher";     // Weathertop Royal Archer, CR 650

const string FRK_GATE_RR   = "q_frk_gate";         // gate placeable blueprint
const string FRK_GATE_DEST = "FRK_DEST";           // local string: dest WP tag

// ------------------------------------------------------------
// Stage accessors (persistent, per character). The stage only advances.

int FRK_GetStage(object oPC)
{
    return GetCampaignInt(FRK_DB, FRK_STAGE, oPC);
}

void FRK_SetStage(object oPC, int nStage)
{
    if (GetCampaignInt(FRK_DB, FRK_STAGE, oPC) >= nStage) return;
    SetCampaignInt(FRK_DB, FRK_STAGE, nStage, oPC);
}

int FRK_HasKey(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, FRK_KEYTAG));
}

// ------------------------------------------------------------
// Stage 1: the key is in hand. Called from acquireditem_tag (fresh pickup) and
// from FRK_LoginCheck (characters who already had it before this shipped).

void FRK_OnKeyAcquired(object oPC)
{
    if (!GetIsPC(oPC)) return;
    if (FRK_GetStage(oPC) >= 1) return;

    FRK_SetStage(oPC, 1);
    AddJournalQuestEntry(FRK_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}

// Retroactive catch-up on login: anyone already carrying the key gets the
// quest. Idempotent -- FRK_OnKeyAcquired bails once the stage is set.
void FRK_LoginCheck(object oPC)
{
    if (!GetIsPC(oPC)) return;
    if (FRK_GetStage(oPC) >= 1) return;
    if (!FRK_HasKey(oPC)) return;

    FRK_OnKeyAcquired(oPC);
}

// ------------------------------------------------------------
// Gate spawning. One blueprint serves both ends of the passage; which way it
// leads is a local string set at spawn time, so there is no second blueprint
// to keep in sync.

// TRUE if a gate is already standing at oWP's area near enough to count. We
// guard per-waypoint rather than by module-wide tag, because both gates share
// the blueprint's tag.
int FRK_GateExistsAt(object oWP)
{
    object oArea = GetArea(oWP);
    object oObj  = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oObj))
    {
        if (GetObjectType(oObj) == OBJECT_TYPE_PLACEABLE
            && GetResRef(oObj) == FRK_GATE_RR)
            return TRUE;
        oObj = GetNextObjectInArea(oArea);
    }
    return FALSE;
}

// Spawn the gate at sWP leading to sDest. No-ops if sWP is not placed yet or a
// gate is already standing there.
void FRK_SpawnGate(string sWP, string sDest)
{
    object oWP = GetWaypointByTag(sWP);
    if (!GetIsObjectValid(oWP)) return;
    if (FRK_GateExistsAt(oWP)) return;

    object oGate = CreateObject(OBJECT_TYPE_PLACEABLE, FRK_GATE_RR,
                                GetLocation(oWP));
    if (GetIsObjectValid(oGate))
        SetLocalString(oGate, FRK_GATE_DEST, sDest);
}

// ------------------------------------------------------------
// Using a gate. Outbound (Noirinan -> Tombs) demands the key; the return gate
// inside the tombs never does, so a player who loses the key is not entombed.

void FRK_UseGate(object oGate, object oPC)
{
    if (!GetIsPC(oPC)) return;

    string sDest = GetLocalString(oGate, FRK_GATE_DEST);
    if (sDest == "") return;

    object oWP = GetWaypointByTag(sDest);
    if (!GetIsObjectValid(oWP)) return;

    int bOutbound = (sDest == FRK_WP_TOMB);

    if (bOutbound && !FRK_HasKey(oPC))
    {
        SendMessageToPC(oPC, "The barrow-gate is sealed. Seven marks are cut "
            + "into the stone, and no hand of yours will move it without the "
            + "key that answers them.");
        return;
    }

    if (bOutbound)
    {
        FRK_SetStage(oPC, 2);
        AddJournalQuestEntry(FRK_QUEST, 2, oPC, FALSE, FALSE, TRUE);
        SendMessageToPC(oPC, "The Forbidden Realms Key turns in a lock you "
            + "cannot see, and the seal gives way.");
    }

    AssignCommand(oPC, ActionJumpToLocation(GetLocation(oWP)));
}

// ------------------------------------------------------------
// Tomb arrival: stage 3 + journal entry 3, once per character.

void FRK_OnTombEntered(object oPC)
{
    if (!GetIsPC(oPC)) return;
    if (FRK_GetStage(oPC) >= 3) return;

    FRK_SetStage(oPC, 3);
    AddJournalQuestEntry(FRK_QUEST, 3, oPC, FALSE, FALSE, TRUE);
}

// ------------------------------------------------------------
// Kill bookkeeping. Called from q_frk_death with the killer's party; the
// journal completes when one character has all three recorded.

void FRK_RecordKill(object oPC, string sKey)
{
    if (!GetIsPC(oPC)) return;
    if (FRK_GetStage(oPC) < 1) return;    // never touched the quest

    SetCampaignInt(FRK_DB, sKey, 1, oPC);

    if (GetCampaignInt(FRK_DB, "frk_king",   oPC) == 1
        && GetCampaignInt(FRK_DB, "frk_queen",  oPC) == 1
        && GetCampaignInt(FRK_DB, "frk_archer", oPC) == 1)
    {
        AddJournalQuestEntry(FRK_QUEST, 10, oPC, FALSE, FALSE, TRUE);
    }
}
