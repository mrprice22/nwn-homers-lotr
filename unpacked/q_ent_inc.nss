// q_ent_inc.nss - The Thirteenth Ent (roadmap: thirteenth-ent)
//
// T4 (level 32 band) restoration quest in Fangorn Forest (area resref
// "fangornforest"). Leaflock, the thirteenth Ent of Fangorn, has stood so
// long that he has gone tree-still and forgotten his own name. Two classes
// can wake him; both end in the same reward, the Draught of the Ent.
//
// DRUID BRANCH (druid level >= 20)
//   * Accepting stamps the questcddb rolling-24h key ENT_CD_DRUID: one
//     attempt per real-world day, win or lose.
//   * Truffles of Fangorn are invisible to hands and eyes. They only appear
//     while a druid with the trial active is standing in the area IN BOAR
//     FORM (wild shape -- GetAppearanceType == APPEARANCE_TYPE_BOAR). The
//     area heartbeat (q_ent_hb, on fangornforest) spawns the truffle
//     placeables at the admin-placed waypoints AP_thirteenthent_2..6 while
//     such a druid is present and clears them again when none is.
//   * Rooting one up (q_ent_pick, the placeable OnUsed) gives the truffle
//     item and opens a SHORT window (ENT_TRUFF_SECS). When it lapses the
//     truffle crumbles and another must be dug.
//   * The ritual itself is a cast of Nature's Balance whose area of effect
//     overlaps Leaflock, with the truffle still in the pack. Detected in
//     ENT_OnSpellCast(), called from stop_spellcheat.nss -- the module's
//     SetModuleOverrideSpellscript hook installed by onmoduleload.nss (the
//     same non-destructive route fat_inc.nss uses). No stock spell script is
//     replaced.
//
// BARD BRANCH (bard level >= 20)
//   * Accepting stamps ENT_CD_BARD (rolling 24h) and starts a two-stage
//     concert. Leaflock gives a visible cue (he stirs / speaks) and the bard
//     answers it by using the Bard Song feat within ENT_CUE_SECS.
//   * Each song rolls BOTH Lore and Perform, d20 + skill rank, and prints
//     every roll to the player. Stage 1 is DC 30 / DC 30, stage 2 is
//     DC 40 / DC 40. A single failed check ends the attempt (the 24h wait
//     was already stamped at the start).
//   * Bard Song is detected in ENT_OnBardSong(), reached from
//     nw_s2_bardsong.nss (the module's own Bard Song override, which is the
//     real ImpactScript of spells.2da row "Bards_Song") via
//     ExecuteScript("q_ent_song") -- the song's own behaviour is untouched.
//
// REWARD - Draught of the Ent (blueprint q_ent_drght, item tag q_ent_drink):
//   a permanent +1 STR / +1 CON, written into the character's BASE scores via
//   NWNX_Creature (the route legfeat_inc.nss uses for its RAW-kind feats).
//   Non-farmable at two independent points, both advance-only questcddb
//   calendar keys that no relog or reboot resets:
//     ENT_DRAUGHT_K  - the draught is HANDED OUT at most once per character
//     ENT_DRUNK_K    - the draught is DRUNK for effect at most once per
//                      character (q_ent_drink.nss re-checks before applying)
//   and the ritual itself re-verifies truffle possession at grant time, so
//   the drop-item-mid-conversation farm cannot reach the reward.
//
// Everything here no-ops gracefully if the admin has not yet placed the
// AP_thirteenthent_* waypoints: no Ent, no truffles, no errors.

#include "quest_cd_inc"

// ------------------------------------------------------------
// Identity

const string ENT_JOURNAL     = "thirteenthent";   // module.jrl.json category tag
const string ENT_RES         = "q_ent_13th";      // Ent blueprint resref
const string ENT_TAG         = "q_ent_13th";      // Ent tag
const string ENT_WP_GIVER    = "AP_thirteenthent_1";
const string ENT_WP_TRUFFLE  = "AP_thirteenthent_";  // + "2".."6"
const int    ENT_TRUFFLE_WPS = 6;                 // last truffle waypoint index

const string ENT_TRUFP_RES   = "q_ent_trufp";     // truffle placeable
const string ENT_TRUFP_TAG   = "q_ent_trufp";
const string ENT_TRUFF_RES   = "q_ent_truff";     // truffle item
const string ENT_TRUFF_TAG   = "q_ent_truff";
const string ENT_DRAUGHT_RES = "q_ent_drght";     // draught item blueprint
const string ENT_DRAUGHT_TAG = "q_ent_drink";     // ... and its tag-based script

// questcddb keys (all real-world time, survive reboots and relogs)
const string ENT_CD_DRUID    = "ent13_druid_try";
const string ENT_CD_BARD     = "ent13_bard_try";
const string ENT_DONE_K      = "ent13_restored";
const string ENT_DRAUGHT_K   = "ent13_draught";
const string ENT_DRUNK_K     = "ent13_draught_drunk";

// Per-attempt scratch state, on the PC
const string ENT_L_DRUID     = "ent13_druid";        // druid trial active
const string ENT_L_TRUFFLE   = "ent13_truffle_ok";   // truffle still fresh
const string ENT_L_STAGE     = "ent13_bard_stage";   // 0 / 1 / 2
const string ENT_L_CUE       = "ent13_cue";          // cue is live, sing now
const string ENT_L_SEQ       = "ent13_seq";          // invalidates stale delays

const int    ENT_MIN_LEVEL   = 20;     // druid or bard class level
const float  ENT_REACH       = 10.0;   // RADIUS_SIZE_COLOSSAL, "overlaps the Ent"
const float  ENT_TRUFF_SECS  = 180.0;  // truffle stays fresh this long
const float  ENT_CUE_DELAY   = 8.0;    // pause before Leaflock gives a cue
const float  ENT_CUE_SECS    = 90.0;   // how long a cue stays answerable
const int    ENT_DC_STAGE1   = 30;
const int    ENT_DC_STAGE2   = 40;
const int    ENT_TOKEN_CD    = 6390;   // "come back in <CUSTOM6390>"

// ------------------------------------------------------------
// Small helpers

// TRUE once this character has woken Leaflock (advance-only, forever).
int ENT_IsRestored(object oPC)
{
    return QCD_LastStamp(oPC, ENT_DONE_K) != 0;
}

int ENT_IsDruid(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_DRUID, oPC) >= ENT_MIN_LEVEL;
}

int ENT_IsBard(object oPC)
{
    return GetLevelByClass(CLASS_TYPE_BARD, oPC) >= ENT_MIN_LEVEL;
}

// The living Ent, or OBJECT_INVALID while the waypoint is unplaced.
object ENT_GetEnt()
{
    return GetObjectByTag(ENT_TAG);
}

// Leaflock speaks (silently no-ops if he is not spawned).
void ENT_Say(string sText)
{
    object oEnt = ENT_GetEnt();
    if (GetIsObjectValid(oEnt))
        AssignCommand(oEnt, SpeakString(sText));
}

void ENT_Tell(object oPC, string sText)
{
    SendMessageToPC(oPC, sText);
    FloatingTextStringOnCreature(sText, oPC, FALSE);
}

// Wipe every scratch local of an attempt and invalidate pending delays.
void ENT_ClearState(object oPC)
{
    SetLocalInt(oPC, ENT_L_SEQ, GetLocalInt(oPC, ENT_L_SEQ) + 1);
    DeleteLocalInt(oPC, ENT_L_DRUID);
    DeleteLocalInt(oPC, ENT_L_TRUFFLE);
    DeleteLocalInt(oPC, ENT_L_STAGE);
    DeleteLocalInt(oPC, ENT_L_CUE);
}

// Destroy any truffle this PC is carrying (they never outlive an attempt).
void ENT_BurnTruffles(object oPC)
{
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        object oNext = GetNextItemInInventory(oPC);
        if (GetTag(oItem) == ENT_TRUFF_TAG)
            DestroyObject(oItem);
        oItem = oNext;
    }
}

// ------------------------------------------------------------
// The Ent himself

// (Re)spawn Leaflock at his waypoint. No-ops until the admin places
// AP_thirteenthent_1, and never double-spawns.
void ENT_SpawnEnt()
{
    object oWP = GetWaypointByTag(ENT_WP_GIVER);
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag(ENT_TAG)))
        CreateObject(OBJECT_TYPE_CREATURE, ENT_RES, GetLocation(oWP));
}

// ------------------------------------------------------------
// Truffles

// Are the truffle placeables currently standing?
int ENT_TrufflesUp()
{
    return GetIsObjectValid(GetObjectByTag(ENT_TRUFP_TAG));
}

// Raise the hidden truffles at AP_thirteenthent_2..N. Idempotent, and a
// no-op for every waypoint the admin has not placed yet.
void ENT_SpawnTruffles()
{
    int i;
    for (i = 2; i <= ENT_TRUFFLE_WPS; i++)
    {
        object oWP = GetWaypointByTag(ENT_WP_TRUFFLE + IntToString(i));
        if (!GetIsObjectValid(oWP)) continue;

        // One truffle per waypoint: skip a waypoint that already has one.
        object oNear = GetNearestObjectByTag(ENT_TRUFP_TAG, oWP, 1);
        if (GetIsObjectValid(oNear) && GetDistanceBetween(oNear, oWP) < 1.0)
            continue;

        CreateObject(OBJECT_TYPE_PLACEABLE, ENT_TRUFP_RES, GetLocation(oWP));
    }
}

// Sink them again when no boar-shaped druid is left in the wood.
void ENT_ClearTruffles(object oArea)
{
    object oObj = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oObj))
    {
        object oNext = GetNextObjectInArea(oArea);
        if (GetTag(oObj) == ENT_TRUFP_TAG)
            DestroyObject(oObj);
        oObj = oNext;
    }
}

// TRUE for a druid who is mid-trial and currently wearing the boar.
int ENT_IsTruffleHunter(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return FALSE;
    if (!GetLocalInt(oPC, ENT_L_DRUID)) return FALSE;
    return GetAppearanceType(oPC) == APPEARANCE_TYPE_BOAR;
}

// The truffle went stale: crumble it and say so. nSeq guards against an old
// attempt's timer firing into a new one.
void ENT_TruffleExpire(object oPC, int nSeq)
{
    if (!GetIsObjectValid(oPC)) return;
    if (GetLocalInt(oPC, ENT_L_SEQ) != nSeq) return;
    if (!GetLocalInt(oPC, ENT_L_TRUFFLE)) return;

    DeleteLocalInt(oPC, ENT_L_TRUFFLE);
    ENT_BurnTruffles(oPC);
    ENT_Tell(oPC, "The truffle blackens in your hand and crumbles to dry earth. "
                + "You will have to root up another.");
}

// ------------------------------------------------------------
// Completion and reward

// Hand over the Draught of the Ent, at most once per character, ever.
void ENT_GrantDraught(object oPC)
{
    if (QCD_LastStamp(oPC, ENT_DRAUGHT_K) != 0)
    {
        ENT_Tell(oPC, "Leaflock has no second draught for you -- that gift is "
                    + "given once and once only.");
        return;
    }

    QCD_Stamp(oPC, ENT_DRAUGHT_K);
    CreateItemOnObject(ENT_DRAUGHT_RES, oPC, 1);
    ENT_Tell(oPC, "Leaflock presses a horn cup into your hands: the Draught of the Ent.");
}

// The Ent wakes. Shared end of both branches.
void ENT_Complete(object oPC)
{
    ENT_ClearState(oPC);
    ENT_BurnTruffles(oPC);

    if (!ENT_IsRestored(oPC))
    {
        QCD_Stamp(oPC, ENT_DONE_K);
        AddJournalQuestEntry(ENT_JOURNAL, 4, oPC);
        GiveXPToCreature(oPC, 4000);
    }

    object oEnt = ENT_GetEnt();
    if (GetIsObjectValid(oEnt))
    {
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_SUNSTRIKE), oEnt);
        AssignCommand(oEnt, PlayAnimation(ANIMATION_FIREFORGET_VICTORY1, 1.0, 3.0));
    }

    ENT_Say("Hoom, HOM! It comes back to me... Leaflock. Leaflock is my name, and "
          + "I am awake. Root-friend, you have my thanks, and thanks are slow "
          + "things here -- take this with them.");

    ENT_GrantDraught(oPC);

    DelayCommand(9.0, ENT_Say("Now I will stand a while and listen to the wood. "
                            + "Not so deep, this time. Not so deep."));
}

// ------------------------------------------------------------
// Druid branch: the Nature's Balance ritual

// Called on EVERY spell cast, from stop_spellcheat.nss (the module override
// spellscript). OBJECT_SELF is the caster.
void ENT_OnSpellCast()
{
    if (GetSpellId() != SPELL_NATURES_BALANCE) return;

    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (!GetLocalInt(oPC, ENT_L_DRUID)) return;

    object oEnt = ENT_GetEnt();
    if (!GetIsObjectValid(oEnt)) return;

    location lSpell = GetSpellTargetLocation();
    if (!GetIsObjectValid(GetAreaFromLocation(lSpell)))
        lSpell = GetLocation(oPC);

    if (GetDistanceBetweenLocations(lSpell, GetLocation(oEnt)) > ENT_REACH)
    {
        ENT_Tell(oPC, "Your Balance settles over the wood -- but not over "
                    + "Leaflock's roots. Cast it where it covers him.");
        return;
    }

    // Reward-and-take: re-verify the truffle AT GRANT TIME. The dialogue
    // conditional proves nothing here -- a truffle dropped a moment ago must
    // not buy a draught.
    object oTruffle = GetItemPossessedBy(oPC, ENT_TRUFF_TAG);
    if (!GetIsObjectValid(oTruffle))
    {
        ENT_Tell(oPC, "The Balance turns about Leaflock's roots and finds "
                    + "nothing to bind it. You are carrying no truffle.");
        return;
    }

    if (!GetLocalInt(oPC, ENT_L_TRUFFLE))
    {
        ENT_Tell(oPC, "The truffle in your pack is dead earth now. "
                    + "Root up a fresh one.");
        return;
    }

    DestroyObject(oTruffle);
    ENT_Complete(oPC);
}

// ------------------------------------------------------------
// Bard branch: the two-stage concert

void ENT_BardFail(object oPC, string sWhy)
{
    ENT_ClearState(oPC);
    ENT_Tell(oPC, sWhy);
    ENT_Say("Hoom. No. That is not my name, and this is not my waking. "
          + "Go away, singer -- I am going down again for a day and a night.");
}

// The cue stopped being answerable.
void ENT_CueExpire(object oPC, int nSeq)
{
    if (!GetIsObjectValid(oPC)) return;
    if (GetLocalInt(oPC, ENT_L_SEQ) != nSeq) return;
    if (!GetLocalInt(oPC, ENT_L_CUE)) return;

    ENT_BardFail(oPC, "The moment passes unanswered. Leaflock's bark closes over.");
}

// Leaflock stirs: the bard's window to play opens here.
void ENT_BardCue(object oPC, int nSeq)
{
    if (!GetIsObjectValid(oPC)) return;
    if (GetLocalInt(oPC, ENT_L_SEQ) != nSeq) return;

    int nStage = GetLocalInt(oPC, ENT_L_STAGE);
    if (nStage <= 0) return;

    SetLocalInt(oPC, ENT_L_CUE, 1);

    if (nStage == 1)
        ENT_Say("*the bark of the great Ent shifts, and a long creak runs up "
              + "through the trunk* Hoom... hoom... something is playing.");
    else
        ENT_Say("*roots grind in the loam; a voice comes slowly out of the wood* "
              + "Hoom... more, singer. My name. Fetch me up my name.");

    ENT_Tell(oPC, "Leaflock stirs. Play now -- use your Bard Song.");
    DelayCommand(ENT_CUE_SECS, ENT_CueExpire(oPC, nSeq));
}

// One skill check, reported to the player. Returns TRUE on a pass.
int ENT_Check(object oPC, int nSkill, string sLabel, int nDC)
{
    int nRoll  = d20();
    int nRank  = GetSkillRank(nSkill, oPC);
    int nTotal = nRoll + nRank;
    int bPass  = nTotal >= nDC;

    ENT_Tell(oPC, sLabel + " check: " + IntToString(nRoll) + " + "
                + IntToString(nRank) + " = " + IntToString(nTotal)
                + " vs DC " + IntToString(nDC) + " -- "
                + (bPass ? "SUCCESS" : "FAILURE"));
    return bPass;
}

// Called from q_ent_song.nss, which nw_s2_bardsong.nss executes on every use
// of the Bard Song feat. OBJECT_SELF there is the bard.
void ENT_OnBardSong()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nStage = GetLocalInt(oPC, ENT_L_STAGE);
    if (nStage <= 0) return;

    object oEnt = ENT_GetEnt();
    if (!GetIsObjectValid(oEnt)) return;

    if (GetDistanceBetween(oPC, oEnt) > ENT_REACH)
    {
        ENT_Tell(oPC, "Your song does not carry that far into the wood. "
                    + "Play where Leaflock can hear you.");
        return;
    }

    if (!GetLocalInt(oPC, ENT_L_CUE))
    {
        ENT_Tell(oPC, "Leaflock has not stirred yet. Nothing good is said in "
                    + "a hurry -- wait for his cue.");
        return;
    }

    DeleteLocalInt(oPC, ENT_L_CUE);

    int nDC = (nStage == 1) ? ENT_DC_STAGE1 : ENT_DC_STAGE2;
    int bLore    = ENT_Check(oPC, SKILL_LORE,    "Lore",    nDC);
    int bPerform = ENT_Check(oPC, SKILL_PERFORM, "Perform", nDC);

    if (!bLore || !bPerform)
    {
        ENT_BardFail(oPC, "The song slips its footing and the wood goes quiet.");
        return;
    }

    if (nStage == 1)
    {
        SetLocalInt(oPC, ENT_L_STAGE, 2);
        ENT_Tell(oPC, "Leaflock rises out of the root-sleep. Hold the concert "
                    + "-- he will stir again.");
        ENT_Say("Hoom... I am listening now. Do not stop, singer.");
        DelayCommand(ENT_CUE_DELAY, ENT_BardCue(oPC, GetLocalInt(oPC, ENT_L_SEQ)));
        return;
    }

    ENT_Complete(oPC);
}
