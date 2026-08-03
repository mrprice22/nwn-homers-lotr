// q_hob_inc.nss - "Concerning Hobbits" Shire-genealogy quiz (roadmap: concerning-hobbits)
//
// T1 (L5) daily dialogue minigame, journal tag "concern_hob". Odo Proudfoot
// (q_hob_odo), a Hobbiton genealogist, is forever settling a dispute at the
// Ivy Bush over who is cousin to whom. He puts five questions of Shire
// lineage to the PC; answer four of five rightly to win gold, XP and a
// keepsake from the family stores. One attempt per calendar day (UTC), win
// or lose (quest_cd_inc QCD_IsDoneToday / QCD_Stamp).
//
// "The correct answer rotates by season." The bank holds QHOB_COUNT
// questions; a per-season seed (derived from the in-game calendar,
// GetCalendarYear()*4 + season) deterministically picks QHOB_ASKED distinct
// questions (stride offset + k*step mod 16, step odd so coprime with 16) and
// rotates the displayed answer order per question so the correct letter moves
// with the season. Everything is a pure function of (season seed, question
// index), so re-showing a question is idempotent and the whole server shares
// one seasonal dispute.
//
// Odo is script-spawned at waypoint AP_concerninghobbits_1 (Hobbiton) by
// q_hob_spawn, fired from the area OnEnter wrapper q_hob_enter. It no-ops
// gracefully until the admin places the waypoint (see the roadmap item manual_steps)
// and never double-spawns.
//
// Session state (locals on the PC, reset by q_hob_begin):
//   Q_HOB_ACTIVE  1 while a game is running
//   Q_HOB_SEED    the season seed captured at game start
//   Q_HOB_IDX     questions answered so far (0..5)
//   Q_HOB_SCORE   correct answers so far
//   Q_HOB_SLOT    which displayed option (1..4) is correct for the shown q.
//   Q_HOB_LAST    1 if the most recent answer was correct
//   Q_HOB_RESULT  set at game end: 1 = won, 2 = lost
//
// Custom tokens (registered per-display by the StartingConditionals):
//   6420 time until tomorrow          6421 question number / final score
//   6422 question text                6423-6426 answer options 1-4
//   6427 right-answer line            6428 wrong-answer line

#include "quest_cd_inc"

const string QHOB_QUEST  = "concern_hob"; // questcddb key + journal tag
const int    QHOB_COUNT  = 16;            // questions in the bank
const int    QHOB_ASKED  = 5;             // questions per game
const int    QHOB_TO_WIN = 4;             // correct answers needed
const int    QHOB_XP     = 100;           // XP on a win
const int    QHOB_LINES  = 5;             // right/wrong flavor lines each

// ------------------------------------------------------------
// Season seed and "come back tomorrow" countdown.

// In-game season seed: 0..3 season within the year, unique per (year,season)
// so the dispute rotates every season. GetCalendarMonth() is 1..12.
int QHOB_SeasonSeed()
{
    int nMonth  = GetCalendarMonth();          // 1..12
    int nSeason = (nMonth - 1) / 3;            // 0..3
    return GetCalendarYear() * 4 + nSeason;
}

// Seconds until the next UTC midnight (when QCD_IsDoneToday flips back). From
// SQLite so there is no game-clock drift, matching QCD_IsDoneToday's date().
int QHOB_SecsToTomorrow()
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT CAST(strftime('%s', date('now','+1 day')) AS INTEGER)"
        + " - CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Bank index of the k-th question (k = 0..QHOB_ASKED-1) for season seed nSeed.
// step is odd, hence coprime with 16, so the picked indices are distinct.
int QHOB_QAt(int nSeed, int k)
{
    int nOff  = nSeed % QHOB_COUNT;
    int nStep = 2 * ((nSeed / QHOB_COUNT) % 8) + 1;
    return (nOff + k * nStep) % QHOB_COUNT;
}

// ------------------------------------------------------------
// The question bank. QHOB_Opt(i, 0) is always the correct answer; 1..3 are
// plausible distractors (real Shire names). Display order is rotated at show
// time so the correct letter varies with the season.

string QHOB_Q(int i)
{
    switch (i)
    {
        case 0:  return "Bilbo Baggins's mother, a famous Took, was named -- who?";
        case 1:  return "Frodo's mother, who drowned with his father in the Brandywine, was named -- who?";
        case 2:  return "And Frodo's father, who drowned with her, was -- who?";
        case 3:  return "Old Bilbo named which young cousin his heir, and left him Bag End?";
        case 4:  return "Otho Sackville-Baggins, who so coveted Bag End, was wed to which sharp-tongued lady?";
        case 5:  return "Otho and Lobelia's son -- later nicknamed 'Pimple' -- was named -- who?";
        case 6:  return "Samwise Gamgee's father, the old gardener of Bagshot Row, was better known as -- what?";
        case 7:  return "Whom did Samwise Gamgee marry, there in Hobbiton?";
        case 8:  return "Meriadoc Brandybuck's father, the Master of Buckland, was -- who?";
        case 9:  return "Peregrin Took's father, the Thain of the Shire, was -- who?";
        case 10: return "The Old Took, who lived to a hundred and thirty, was named -- who?";
        case 11: return "'Bullroarer' Took, who clubbed a goblin-king's head clean off, was rightly named -- who?";
        case 12: return "Before Bag End, young Frodo was raised at Brandy Hall -- seat of which family?";
        case 13: return "'Fatty' Bolger, left to keep up Frodo's ruse at Crickhollow, was rightly named -- who?";
        case 14: return "The great smials at Tuckborough -- the Great Smials -- are the seat of which family?";
        case 15: return "Bilbo's grand farewell party marked his 'eleventy-first' birthday. That is -- how old?";
    }
    return "";
}

string QHOB_Opt(int i, int j)
{
    switch (i * 4 + j)
    {
        // 0 - Belladonna Took
        case 0:  return "Belladonna Took.";
        case 1:  return "Mirabella Took.";
        case 2:  return "Donnamira Took.";
        case 3:  return "Primula Brandybuck.";
        // 1 - Primula Brandybuck
        case 4:  return "Primula Brandybuck.";
        case 5:  return "Esmeralda Took.";
        case 6:  return "Peony Baggins.";
        case 7:  return "Menegilda Goold.";
        // 2 - Drogo Baggins
        case 8:  return "Drogo Baggins.";
        case 9:  return "Dudo Baggins.";
        case 10: return "Fosco Baggins.";
        case 11: return "Otho Sackville-Baggins.";
        // 3 - Frodo Baggins
        case 12: return "Frodo Baggins.";
        case 13: return "Lotho Sackville-Baggins.";
        case 14: return "Meriadoc Brandybuck.";
        case 15: return "Folco Boffin.";
        // 4 - Lobelia
        case 16: return "Lobelia Bracegirdle.";
        case 17: return "Lalia Clayhanger.";
        case 18: return "Camellia Sackville.";
        case 19: return "Peony Baggins.";
        // 5 - Lotho
        case 20: return "Lotho Sackville-Baggins.";
        case 21: return "Ted Sandyman.";
        case 22: return "Sancho Proudfoot.";
        case 23: return "Otho the Younger.";
        // 6 - the Gaffer
        case 24: return "the Gaffer -- Hamfast Gamgee.";
        case 25: return "Andwise 'Andy' Roper.";
        case 26: return "Daddy Twofoot.";
        case 27: return "Halfred of Overhill.";
        // 7 - Rosie Cotton
        case 28: return "Rosie Cotton.";
        case 29: return "Marigold Gamgee.";
        case 30: return "Pretty Poppy Chubb.";
        case 31: return "Daisy Boffin.";
        // 8 - Saradoc Brandybuck
        case 32: return "Saradoc Brandybuck.";
        case 33: return "Rorimac Brandybuck.";
        case 34: return "Gorbadoc Brandybuck.";
        case 35: return "Merimac Brandybuck.";
        // 9 - Paladin Took
        case 36: return "Paladin Took.";
        case 37: return "Ferumbras Took.";
        case 38: return "Adalgrim Took.";
        case 39: return "Fortinbras Took.";
        // 10 - Gerontius Took
        case 40: return "Gerontius Took.";
        case 41: return "Isengrim Took.";
        case 42: return "Isumbras Took.";
        case 43: return "Bandobras Took.";
        // 11 - Bandobras Took
        case 44: return "Bandobras Took.";
        case 45: return "Gerontius Took.";
        case 46: return "Isengrim Took.";
        case 47: return "Ferumbras Took.";
        // 12 - Brandybuck
        case 48: return "The Brandybucks.";
        case 49: return "The Tooks.";
        case 50: return "The Bolgers.";
        case 51: return "The Boffins.";
        // 13 - Fredegar Bolger
        case 52: return "Fredegar Bolger.";
        case 53: return "Folco Boffin.";
        case 54: return "Odo Proudfoot.";
        case 55: return "Milo Burrows.";
        // 14 - Took
        case 56: return "The Tooks.";
        case 57: return "The Brandybucks.";
        case 58: return "The Bagginses.";
        case 59: return "The Bolgers.";
        // 15 - 111
        case 60: return "A hundred and eleven.";
        case 61: return "A hundred exactly.";
        case 62: return "A hundred and twenty-one.";
        case 63: return "A hundred and thirty-one.";
    }
    return "";
}

// Set answer-option token 6423..6426 for displayed slot nSlot (1..4) of the
// question the PC is on, and return its text. Called one-per-reply from
// q_hob_c_o1..o4 -- setting all four in one loop leaves only the first-written
// token resolving in the reply list in-engine (the riddle-game lesson), so the
// three distractor replies would render empty and be suppressed.
//
// Displayed slot s (0-based) holds data option j where (j + nRot) % 4 == s,
// i.e. j = (s - nRot + 4) % 4. So the correct option (j == 0) lands on slot
// nRot, i.e. Q_HOB_SLOT = nRot + 1 (see q_hob_c_show).
string QHOB_ShowOpt(object oPC, int nSlot)
{
    int nSeed = GetLocalInt(oPC, "Q_HOB_SEED");
    int nIdx  = GetLocalInt(oPC, "Q_HOB_IDX");
    int nQ    = QHOB_QAt(nSeed, nIdx);
    int nRot  = (nSeed + nIdx) % 4;
    int s     = nSlot - 1;                 // 0-based displayed slot
    int j     = (s - nRot + 4) % 4;        // which data option lands here
    string sOpt = QHOB_Opt(nQ, j);
    SetCustomToken(6423 + s, sOpt);
    return sOpt;
}

// ------------------------------------------------------------
// Odo's between-question patter.

string QHOB_RightLine(int k)
{
    switch (k % QHOB_LINES)
    {
        case 0: return "*Odo scratches a tick in the margin.* Just so, just so! You've studied your family-books, I'll grant you.";
        case 1: return "Right as rain! There's a head for lineage. The Ivy Bush could learn a thing from you.";
        case 2: return "Correct, and no mistake. *He dabs sand across the wet ink.* On we go.";
        case 3: return "Aye, that's the one! Half of Hobbiton gets that wrong, you know.";
        case 4: return "Quite right. *He nods, whiskers bobbing.* A friend of the family-books, plainly.";
    }
    return "";
}

string QHOB_WrongLine(int k)
{
    switch (k % QHOB_LINES)
    {
        case 0: return "*Odo winces and shakes his head.* No, no -- a common muddle, that. Mark it and move on.";
        case 1: return "Bless me, no. You've crossed your Bagginses with your Boffins there. Next!";
        case 2: return "Wrong, I'm afraid. The Ivy Bush would have your ears for that one. On we go.";
        case 3: return "*He sighs.* Not so. Half the Shire says the same and half the Shire is wrong.";
        case 4: return "Ah, no. A tidy guess, but the family-book says otherwise. Next question.";
    }
    return "";
}

// ------------------------------------------------------------
// Reward on a win: modest T1 payout -- 40-100 gp, QHOB_XP, and a keepsake
// from the family stores. A perfect 5/5 upgrades the keepsake to the Greater
// Ring of Scholars. Both prizes are existing module blueprints (verified in
// unpacked/), so they always resolve.

void QHOB_PayOut(object oPC, int nScore)
{
    GiveGoldToCreature(oPC, 40 + Random(61));
    GiveXPToCreature(oPC, QHOB_XP);
    if (nScore >= QHOB_ASKED)
        CreateItemOnObject("grscholar", oPC, 1);   // perfect 5/5 bonus
    else
        CreateItemOnObject("witchbud", oPC, 1);     // a pouch of pipe-weed
}

// ------------------------------------------------------------
// Core answer handler, shared by q_hob_a1..a4. nSlot = the displayed option
// (1..4) chosen. On the fifth answer the game is finalized here -- stamp,
// journal, payout -- so escape-closing on the result line cannot dodge the
// daily stamp or lose a paid-out prize.

void QHOB_Answer(object oPC, int nSlot)
{
    if (!GetLocalInt(oPC, "Q_HOB_ACTIVE")) return;
    int nIdx = GetLocalInt(oPC, "Q_HOB_IDX");
    if (nIdx >= QHOB_ASKED) return;

    int nRight = (nSlot == GetLocalInt(oPC, "Q_HOB_SLOT"));
    SetLocalInt(oPC, "Q_HOB_LAST", nRight);
    if (nRight)
        SetLocalInt(oPC, "Q_HOB_SCORE", GetLocalInt(oPC, "Q_HOB_SCORE") + 1);

    nIdx++;
    SetLocalInt(oPC, "Q_HOB_IDX", nIdx);
    if (nIdx < QHOB_ASKED) return;

    // Fifth answer -- game over. One attempt per day, win or lose.
    DeleteLocalInt(oPC, "Q_HOB_ACTIVE");
    int nScore = GetLocalInt(oPC, "Q_HOB_SCORE");
    int nWon   = (nScore >= QHOB_TO_WIN);
    SetLocalInt(oPC, "Q_HOB_RESULT", nWon ? 1 : 2);

    if (QCD_IsDoneToday(oPC, QHOB_QUEST)) return; // paranoid double-pay guard
    QCD_Stamp(oPC, QHOB_QUEST);
    AddJournalQuestEntry(QHOB_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    if (nWon)
        QHOB_PayOut(oPC, nScore);
}
