// q_rid_inc.nss - The Riddle Game shared helpers (roadmap: riddle-game)
//
// T1 weekly dialogue minigame, journal tag "riddle_game". A whispering
// wretch (q_rid_wretch - strongly implied to be, but never named, Gollum)
// squats in Bree Cave and plays the old game: seven riddles, answered by
// dialogue choice. Five or more right of seven wins a prize from its hoard;
// fewer wins nothing but taunting. One attempt per calendar week
// (quest_cd_inc QCD_IsDoneThisWeek - resets at the start of the ISO week,
// UTC, matching the "weekly" intent; win or lose, the week is stamped).
//
// The wretch is script-spawned at waypoint AP_riddlegame_1 (Bree Cave) by
// q_rid_spawn, fired from the area's OnEnter wrapper q_rid_enter. It no-ops
// gracefully until the admin places the waypoint, and never double-spawns.
// The placed CR-1029 Gollum boss (gollum.utc, Roll of the Fallen) is a
// completely separate blueprint and is untouched.
//
// Weekly riddle set: the bank holds QRID_COUNT riddles; each ISO week a
// deterministic seed (strftime('%Y%W') as an integer, so the whole server
// shares one weekly set) picks QRID_ASKED distinct riddles via a
// stride-through-the-bank walk (offset + k*step mod 16, step odd so it is
// coprime with 16), and rotates the displayed answer order per riddle so
// the correct letter moves around. A mid-game relog just clears the session
// locals - the game restarts from riddle one (same weekly set); the weekly
// stamp is only written when the seventh answer lands.
//
// Session state (locals on the PC, cleared/reset by q_rid_begin):
//   Q_RID_ACTIVE  1 while a game is running
//   Q_RID_SEED    the week seed captured at game start
//   Q_RID_IDX     riddles answered so far (0..7)
//   Q_RID_SCORE   correct answers so far
//   Q_RID_SLOT    which displayed option (1..4) is correct for the shown riddle
//   Q_RID_LAST    1 if the most recent answer was correct
//   Q_RID_RESULT  set at game end: 1 = won, 2 = lost
//
// Custom tokens (registered per-display by the StartingConditionals):
//   6360 time until the week turns    6361 riddle number / final score
//   6362 riddle verse                 6363-6366 answer options 1-4
//   6367 right-answer quip            6368 wrong-answer taunt

#include "quest_cd_inc"

const string QRID_QUEST  = "riddle_game";  // questcddb key + journal tag
const int    QRID_COUNT  = 16;             // riddles in the bank
const int    QRID_ASKED  = 7;              // riddles per game
const int    QRID_TO_WIN = 5;              // correct answers needed
const int    QRID_XP     = 250;            // XP on a win
const int    QRID_QUIPS  = 5;              // right/wrong flavor lines each

// ------------------------------------------------------------
// Weekly seed and week-turn countdown (both from SQLite so there is no
// game-clock drift; %Y%W matches QCD_IsDoneThisWeek's %Y-%W week).

int QRID_WeekSeed()
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT CAST(strftime('%Y%W','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Seconds until the next ISO week begins (Monday 00:00 UTC). 'weekday 1'
// after '+1 day' always lands on the NEXT Monday, even on a Monday.
int QRID_SecsToNextWeek()
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT CAST(strftime('%s', date('now','+1 day','weekday 1')) AS INTEGER)"
        + " - CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Bank index of the k-th riddle (k = 0..6) of the week seeded nSeed.
// step is odd, hence coprime with 16, so the 7 indices are distinct.
int QRID_RiddleAt(int nSeed, int k)
{
    int nOff  = nSeed % QRID_COUNT;
    int nStep = 2 * ((nSeed / QRID_COUNT) % 8) + 1;
    return (nOff + k * nStep) % QRID_COUNT;
}

// ------------------------------------------------------------
// The riddle bank. Classic Hobbit-style riddles (the old chestnuts
// reworded, plus originals in the same voice). QRID_Opt(i, 0) is always
// the correct answer; 1..3 are distractors. Display order is rotated at
// show time so the correct letter varies.

string QRID_Verse(int i)
{
    switch (i)
    {
        case 0: return "Thirty white ponies stand on a hill of red: first they champ, then they stamp, then they stand still instead.";
        case 1: return "It cannot be seen and cannot be felt, cannot be heard and cannot be smelt. It lies behind the stars and under the hills; every empty hole it fills.";
        case 2: return "No hinge has it, nor key, nor lid, yet inside it a golden treasure is hid.";
        case 3: return "It devours all things: bird and beast, tree and flower; it gnaws iron and bites steel, and grinds the tall mountains down to meal.";
        case 4: return "It lives without breathing, cold as the grave; never thirsty, yet always drinking; clad all in mail that never clinks.";
        case 5: return "Without a voice it cries, without wings it flutters; without teeth it bites, without a mouth it mutters.";
        case 6: return "Its roots no eye has ever seen; it stands taller than the tallest trees. Up and up and up it goes, and yet it never grows.";
        case 7: return "An eye set in a blue face beheld an eye in a green face. 'That eye is like this eye,' said the first, 'only set in a low place, and not in a high place.'";
        case 8: return "Round it is, yet never whole; lighter than a whisper, heavier than a hill of gold. Most itself upon a finger, most dangerous in a pocket.";
        case 9: return "All day it follows at your heel like a faithful hound; at evening it grows monstrous tall; it dies the moment the candle does.";
        case 10: return "It belongs to you and to no one else, precious -- yet other people use it far more often than you do.";
        case 11: return "Tall when it is young, short when it is old; all its life it wears a crown of fire, and one small breath is its death.";
        case 12: return "It runs but never walks, it murmurs but never talks; it has a bed but never sleeps, it has a mouth but never eats.";
        case 13: return "Speak its name aloud, even once, and it is gone.";
        case 14: return "You make them with every step and carry them on every road, yet you always leave every one of them behind you.";
        case 15: return "It is always coming but never arrives; and when at last you meet it, it has already changed its name.";
    }
    return "";
}

string QRID_Opt(int i, int j)
{
    switch (i * 4 + j)
    {
        // 0 - teeth
        case 0:  return "Teeth in a mouth.";
        case 1:  return "The horses of the Rohirrim.";
        case 2:  return "Millstones grinding.";
        case 3:  return "Dwarves at supper.";
        // 1 - the dark
        case 4:  return "The dark.";
        case 5:  return "A wraith.";
        case 6:  return "The cold wind off the mountains.";
        case 7:  return "Fear.";
        // 2 - an egg
        case 8:  return "An egg.";
        case 9:  return "A dragon's hoard.";
        case 10: return "A barrow-mound.";
        case 11: return "A casket of mithril.";
        // 3 - time
        case 12: return "Time.";
        case 13: return "A dragon.";
        case 14: return "The Great Enemy.";
        case 15: return "Rust.";
        // 4 - a fish
        case 16: return "A fish.";
        case 17: return "A barrow-wight.";
        case 18: return "An icicle.";
        case 19: return "A drowned knight.";
        // 5 - the wind
        case 20: return "The wind.";
        case 21: return "A ghost.";
        case 22: return "A guilty conscience.";
        case 23: return "A swarm of midges.";
        // 6 - a mountain
        case 24: return "A mountain.";
        case 25: return "A mallorn of the Golden Wood.";
        case 26: return "A tower of Gondor.";
        case 27: return "An Ent.";
        // 7 - sun on the daisies
        case 28: return "The sun shining on the daisies.";
        case 29: return "The moon mirrored in a pool.";
        case 30: return "A dragon eyeing an emerald.";
        case 31: return "Two elves staring at one another.";
        // 8 - a ring
        case 32: return "A ring.";
        case 33: return "A gold coin.";
        case 34: return "A crown.";
        case 35: return "A promise.";
        // 9 - a shadow
        case 36: return "Your shadow.";
        case 37: return "A hungry dog.";
        case 38: return "Regret.";
        case 39: return "A Black Rider.";
        // 10 - your name
        case 40: return "Your name.";
        case 41: return "Your gold.";
        case 42: return "Your pipe.";
        case 43: return "Your grave.";
        // 11 - a candle
        case 44: return "A candle.";
        case 45: return "A king.";
        case 46: return "A pine tree.";
        case 47: return "A dragon on its hoard.";
        // 12 - a river
        case 48: return "A river.";
        case 49: return "A serpent.";
        case 50: return "An orc-scout.";
        case 51: return "A rumor.";
        // 13 - silence
        case 52: return "Silence.";
        case 53: return "A secret.";
        case 54: return "The dark.";
        case 55: return "A promise.";
        // 14 - footprints
        case 56: return "Footprints.";
        case 57: return "Memories.";
        case 58: return "Debts.";
        case 59: return "Ponies.";
        // 15 - tomorrow
        case 60: return "Tomorrow.";
        case 61: return "The post.";
        case 62: return "Winter.";
        case 63: return "Death.";
    }
    return "";
}

// Set the answer-option custom token (6363..6366) for one displayed slot
// (nSlot = 1..4) of the riddle the PC is currently on, and return its text.
//
// This is called from a per-reply StartingConditional (q_rid_c_o1..o4), one
// SetCustomToken per call, immediately before that reply is rendered. The
// earlier design set all four tokens in a single loop inside q_rid_c_show;
// in-engine only the first-written token survived to the reply list, so the
// three distractor replies rendered empty text and NWN suppressed them -
// leaving only the correct answer. Setting each slot's token from its own
// reply conditional matches how the entry tokens (6361/6362) reliably resolve.
//
// Slot/rotation mapping mirrors q_rid_c_show: displayed slot index s (0-based)
// holds data option j where (j + nRot) % 4 == s, i.e. j = (s - nRot + 4) % 4.
// So the correct option (j == 0) lands on slot nRot, i.e. Q_RID_SLOT = nRot+1.
string QRID_ShowOpt(object oPC, int nSlot)
{
    int nSeed = GetLocalInt(oPC, "Q_RID_SEED");
    int nIdx  = GetLocalInt(oPC, "Q_RID_IDX");
    int nRid  = QRID_RiddleAt(nSeed, nIdx);
    int nRot  = (nSeed + nIdx) % 4;
    int s     = nSlot - 1;                 // 0-based displayed slot
    int j     = (s - nRot + 4) % 4;        // which data option lands here
    string sOpt = QRID_Opt(nRid, j);
    SetCustomToken(6363 + s, sOpt);
    return sOpt;
}

// ------------------------------------------------------------
// Gollum-ism flavor pools for the between-riddle patter.

string QRID_RightQuip(int k)
{
    switch (k % QRID_QUIPS)
    {
        case 0: return "Yesss... it knows that one. Everyone knows that one, precious. The next is harder, oh yes, much harder. Gollum.";
        case 1: return "*It hisses and bites its long fingers.* Right, right! Clever fat one with its clever answers. We hates it, precious, we hates it forever!";
        case 2: return "Gollum! Lucky guess, lucky guess! Luck runs out, precious, it always runs out. Sss...";
        case 3: return "*Its pale eyes narrow to slits.* Correct... Someone told it! Someone whispered, yes! No matter, no matter. The next one has teeth.";
        case 4: return "Right again, curse it and splash it! Old riddles, worn riddles, too easy for sneaky pocketses. The next one comes from deep under the roots, precious.";
    }
    return "";
}

string QRID_WrongTaunt(int k)
{
    switch (k % QRID_QUIPS)
    {
        case 0: return "*It rocks back and forth, choking with wet laughter.* Wrong! Wrong! It doesn't know, precious, it doesn't know! Gollum, gollum!";
        case 1: return "Sss, stupid! Even the fishes know that one, and fishes don't talk. *It grins with too many teeth.* Next riddle, yes?";
        case 2: return "*It drums its long fingers on the stone, delighted.* No, no, NO. Not even close, precious. The dark eats another point, yes it does.";
        case 3: return "Wrong answers taste the sweetest, gollum! It guesses like a troll at a tea party. Shall we go on? Oh yes, we shall.";
        case 4: return "*It whispers to itself.* It missed, precious, it missed... maybe it isn't so clever after all, no, not clever at all. On we goes.";
    }
    return "";
}

// ------------------------------------------------------------
// Reward on a win: 100-300 gp, QRID_XP, and one random minor treasure from
// the hoard (all existing blueprints, verified; nothing above trinket tier
// - the game is T1 and open to level 1).

void QRID_PayOut(object oPC)
{
    GiveGoldToCreature(oPC, 100 + Random(201));
    GiveXPToCreature(oPC, QRID_XP);

    string sPrize;
    switch (d8())
    {
        case 1: sPrize = "nw_it_mpotion003"; break; // Potion of Cure Critical Wounds
        case 2: sPrize = "nw_it_mring009";   break; // Ring of Cyan
        case 3: sPrize = "nw_it_mring010";   break; // Ring of Crimson
        case 4: sPrize = "nw_it_mring011";   break; // Ring of Jade
        case 5: sPrize = "nw_it_gem013";     break; // Alexandrite
        case 6: sPrize = "nw_it_mring001";   break; // Ring of Protection +1
        case 7: sPrize = "nw_it_mring013";   break; // Ring of Scholars
        default: sPrize = "nw_it_mring006";  break; // Ring of Clear Thought +1
    }
    CreateItemOnObject(sPrize, oPC, 1);
}

// ------------------------------------------------------------
// Core answer handler, shared by q_rid_a1..a4. nSlot = the displayed
// option (1..4) the player chose. On the seventh answer the game is
// finalized right here - stamp, journal, payout - so escape-closing the
// dialogue on the result line can never dodge the weekly stamp or lose a
// paid-out prize.

void QRID_Answer(object oPC, int nSlot)
{
    if (!GetLocalInt(oPC, "Q_RID_ACTIVE")) return;
    int nIdx = GetLocalInt(oPC, "Q_RID_IDX");
    if (nIdx >= QRID_ASKED) return;

    int nRight = (nSlot == GetLocalInt(oPC, "Q_RID_SLOT"));
    SetLocalInt(oPC, "Q_RID_LAST", nRight);
    if (nRight)
        SetLocalInt(oPC, "Q_RID_SCORE", GetLocalInt(oPC, "Q_RID_SCORE") + 1);

    nIdx++;
    SetLocalInt(oPC, "Q_RID_IDX", nIdx);
    if (nIdx < QRID_ASKED) return;

    // Seventh answer - game over. One attempt per week, win or lose.
    DeleteLocalInt(oPC, "Q_RID_ACTIVE");
    int nScore = GetLocalInt(oPC, "Q_RID_SCORE");
    int nWon   = (nScore >= QRID_TO_WIN);
    SetLocalInt(oPC, "Q_RID_RESULT", nWon ? 1 : 2);

    if (QCD_IsDoneThisWeek(oPC, QRID_QUEST)) return; // paranoid double-pay guard
    QCD_Stamp(oPC, QRID_QUEST);
    AddJournalQuestEntry(QRID_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (nWon)
        QRID_PayOut(oPC);
}
