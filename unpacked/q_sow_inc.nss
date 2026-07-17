// q_sow_inc.nss -- "Sowing Discord in Bree" shared helpers
// (roadmap: sowing-discord-bree)
//
// T2 (L15+) EVIL daily repeatable, journal tag "sowing_discord". Bill Ferny
// (the existing placed NPC in Bree, conversation ferny_convo2) pays for a
// bit of quiet mischief: three forged letters -- ugly accusations in other
// people's handwriting -- slipped under three DIFFERENT tables in the
// Prancing Pony, each planted while moving in STEALTH MODE (the same
// deterministic GetActionMode / ACTION_MODE_STEALTH test the Quiet Knives
// dead drop uses -- no dice; come to a table openly and the plant fails
// with a retry message, nothing lost). The three tables are existing
// placed instances in theprancingpo001.git.json, retagged SowDrop1..3 and
// made usable, OnUsed q_sow_plant; a table that already holds this PC's
// letter refuses a second one (per-PC local marked on the placeable --
// clears on server reset, which is harmless: the letters are what carry
// the real progress).
//
// After the third letter goes under a table, the forgeries do their work:
// QSOW_SHERIFF_DELAY seconds later ("the sheriff arrives after N
// heartbeats") the Sheriff of Bree (q_sow_sherf, a level-16 clone of the
// Guardian of Bree, CR 16) and one regular Guardian of Bree (existing
// breelocal001, CR 11) burst in at the last table planted, and both turn
// on the planter (SetIsTemporaryEnemy + ActionAttack -- the q_potd_provoke
// idiom, so the rest of the taproom is not dragged into a faction war).
// Surviving or escaping is not tracked; walk back to Ferny and get paid.
//
// Rewards (q_sow_pay): 500-800 gp of "morgul-silver", 500 XP, and on the
// FIRST completion only the Morgul-Weave Cloak (q_sow_cloak: Bluff +3,
// Hide +3, Saves vs Fear +3 -- the prestige-reward power tier, no
// AB/damage). Repeat completions pay gold + XP only.
//
// Cooldown: rolling daily via the shared quest_cd_inc helper --
// QCD_IsOnCooldown(oPC, "sowing_discord", QCD_DAY), stamped at turn-in.
// (Fittingly, quest_cd_inc's own usage example was a Ferny daily.)
// Progress survives relogs and reboots without locals: "in progress" is
// simply carrying a forged letter (plot + cursed, can't be dropped or
// sold), and "ready to turn in" is a second questcddb stamp key,
// "sowing_discord_plant", written when the third letter lands -- ready ==
// plant stamp newer than the last turn-in stamp, with no letters held.
// If the letters are ever lost without being planted, the PC simply has
// no letters and no fresh plant stamp, so the offer comes back (after the
// cooldown, if any) and re-accepting re-issues a fresh set.
//
// Gates on the offer: total level 15+ (GetHitDice) and not Good-aligned
// (GetAlignmentGoodEvil != ALIGNMENT_GOOD -- a soft "evil-ish" gate; Good
// PCs just never hear the whisper and get ordinary Ferny). No faction/
// reputation changes: the faction-scaffolding roadmap item hasn't shipped
// yet, so rep integration is deliberately skipped for now.
//
// Custom token: 6390 -- time left on the daily cooldown for Ferny's
// "come back in <CUSTOM6390>" greeting (q_sow_c_cd).

#include "quest_cd_inc"

const string QSOW_QUEST      = "sowing_discord";        // journal tag + turn-in stamp
const string QSOW_PLANT      = "sowing_discord_plant";  // third-letter stamp key
const string QSOW_LETTER_RES = "q_sow_letter";          // forged letter blueprint
const string QSOW_LETTER_TAG = "SowForgedLetter";
const string QSOW_CLOAK_RES  = "q_sow_cloak";           // first-completion reward
const string QSOW_CLOAK_TAG  = "MorgulWeaveCloak";
const string QSOW_SHERF_RES  = "q_sow_sherf";           // Sheriff of Bree blueprint
const string QSOW_DEPUTY_RES = "breelocal001";          // existing Guardian of Bree

const int   QSOW_LETTERS       = 3;      // letters issued / tables to plant
const int   QSOW_LEVEL         = 15;     // minimum total level for the offer
const int   QSOW_XP            = 500;    // XP per completion
const int   QSOW_GOLD_BASE     = 500;    // gold: base + Random(spread+1) = 500-800
const int   QSOW_GOLD_SPREAD   = 300;
const float QSOW_SHERIFF_DELAY = 18.0;   // seconds from third plant to the law (~3 heartbeats)
const int   QSOW_TOKEN_CD      = 6390;   // cooldown span token

// ------------------------------------------------------------
// Progress predicates (all persistent -- items + questcddb stamps only).

// How many forged letters oPC still carries.
int QSOW_LettersHeld(object oPC)
{
    int n = 0;
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == QSOW_LETTER_TAG) n++;
        oItem = GetNextItemInInventory(oPC);
    }
    return n;
}

// TRUE while oPC is mid-job (still carrying at least one letter).
int QSOW_InProgress(object oPC)
{
    return GetIsObjectValid(GetItemPossessedBy(oPC, QSOW_LETTER_TAG));
}

// TRUE when the third letter has been planted and Ferny hasn't paid yet:
// the plant stamp is newer than the last turn-in stamp, and no letters
// remain in hand.
int QSOW_ReadyToTurnIn(object oPC)
{
    if (QSOW_InProgress(oPC)) return FALSE;
    int nPlanted = QCD_LastStamp(oPC, QSOW_PLANT);
    return nPlanted > 0 && nPlanted > QCD_LastStamp(oPC, QSOW_QUEST);
}

// The deterministic stealth test shared with the Quiet Knives drop: the
// toggled stealth mode, no skill roll, no dice.
int QSOW_IsUnseen(object oPC)
{
    return GetActionMode(oPC, ACTION_MODE_STEALTH);
}

// ------------------------------------------------------------
// The law arrives. Called by DelayCommand from q_sow_plant (running on the
// last table planted) QSOW_SHERIFF_DELAY seconds after the third letter.
// Spawns the Sheriff of Bree + one Guardian of Bree at the table and turns
// both on the planter only (temporary enemy -- no faction-wide brawl in
// the taproom). If the planter has already left the area or logged out,
// the pair just stand there muttering, which is fine.
void QSOW_SheriffArrives(location lWhere, object oPC)
{
    object oSheriff = CreateObject(OBJECT_TYPE_CREATURE, QSOW_SHERF_RES, lWhere);
    object oDeputy  = CreateObject(OBJECT_TYPE_CREATURE, QSOW_DEPUTY_RES, lWhere);

    if (GetIsObjectValid(oSheriff))
        AssignCommand(oSheriff, SpeakString(
            "Forgeries! Poison-pen filth, under the tables of MY town -- "
            + "and there stands the rat that planted it. Take them!",
            TALKVOLUME_TALK));

    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return;
    if (GetArea(oPC) != GetAreaFromLocation(lWhere)) return;

    if (GetIsObjectValid(oSheriff))
    {
        SetIsTemporaryEnemy(oPC, oSheriff);
        AssignCommand(oSheriff, ActionAttack(oPC));
    }
    if (GetIsObjectValid(oDeputy))
    {
        SetIsTemporaryEnemy(oPC, oDeputy);
        AssignCommand(oDeputy, ActionAttack(oPC));
    }
}
