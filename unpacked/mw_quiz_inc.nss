//::///////////////////////////////////////////////
//:: mw_quiz_inc -- MeaningWave guide quiz engine.
//::
//:: Drives a data-driven quiz from the per-guide banks in mw_quiz_data. For each
//:: run we draw MW_QUIZ_DRAW questions at random (no repeats) from the guide's
//:: 20-question bank, and shuffle the four answer choices into random display
//:: slots. Pass MW_QUIZ_PASS of MW_QUIZ_DRAW to unlock. Correctness is tracked in
//:: per-PC LocalInts keyed by guide name; nothing is stored in the dialogue tree.
//::
//:: Runtime tokens (module-global). They are populated by the reply that LEADS
//:: INTO each question node -- the "begin" reply draws question 1, and each answer
//:: reply scores the current question then draws the next -- so the tokens are set
//:: before the following entry renders. This is the same ordering the forge relies
//:: on (a reply's Actions Taken runs before the entry it links to is displayed;
//:: see forge_stg_* -> bellnius_smith.dlg). Setting them on the question entry's
//:: own Actions Taken instead is unreliable (the entry text can render against the
//:: PREVIOUS load), which desynced the displayed question from the scored answer.
//::   7000 = question prompt
//::   7001..7004 = the four answer choices (shuffled)
//::   7005 = "Question N of 5" progress label
//::
//:: Per-PC state (guide = full name, e.g. "jocko"):
//::   mw_active            (String) guide whose quiz is in progress
//::   mw_<guide>_n         questions asked so far this run (0..DRAW)
//::   mw_<guide>_score     running correct count
//::   mw_<guide>_used      bitmask of bank indices already drawn this run
//::   mw_<guide>_cor       display slot (1..4) holding the correct answer now
//::
//:: Multiplayer note: SetCustomToken is module-global, so two PCs mid-quiz could
//:: momentarily see each other's choice text. This is the accepted limitation of
//:: every token system in the module (merit, forge, boss board); the window is a
//:: single synchronous node render. No mitigation attempted.
//:://////////////////////////////////////////////

#include "mw_unlock_inc"
#include "mw_quiz_data"

const int MW_QUIZ_DRAW = 5;   // questions asked per run
const int MW_QUIZ_PASS = 4;   // correct answers needed to unlock
const int MW_QUIZ_OPTS = 4;   // answer choices per question

// Return the idx-th '~'-delimited field of a packed quiz row.
string MW_Field(string sRow, int idx)
{
    int i;
    int p;
    for (i = 0; i < idx; i++)
    {
        p = FindSubString(sRow, "~");
        if (p < 0) return "";
        sRow = GetSubString(sRow, p + 1, GetStringLength(sRow) - p - 1);
    }
    p = FindSubString(sRow, "~");
    if (p < 0) return sRow;              // last field
    return GetSubString(sRow, 0, p);
}

// Begin a fresh run: clear all per-run state and mark this guide active.
// The "begin" reply (mw_q_start) calls this and then MW_QuizLoad, so question 1's
// tokens are set before the first question entry renders.
void MW_QuizStart(object oPC, string sGuide)
{
    DeleteLocalInt(oPC, "mw_" + sGuide + "_n");
    DeleteLocalInt(oPC, "mw_" + sGuide + "_score");
    DeleteLocalInt(oPC, "mw_" + sGuide + "_used");
    DeleteLocalInt(oPC, "mw_" + sGuide + "_cor");
    SetLocalString(oPC, "mw_active", sGuide);
}

// Draw the next unused random question, shuffle its choices into tokens 7001-7004,
// record which slot is correct, and advance the progress counter/token.
void MW_QuizLoad(object oPC, string sGuide)
{
    int nTotal = MW_QCount(sGuide);
    int nUsed  = GetLocalInt(oPC, "mw_" + sGuide + "_used");

    // Pick a random index whose bit is not yet set. Guaranteed to terminate:
    // we only ever draw MW_QUIZ_DRAW (< nTotal) questions per run.
    int idx;
    do { idx = Random(nTotal); } while (nUsed & (1 << idx));
    SetLocalInt(oPC, "mw_" + sGuide + "_used", nUsed | (1 << idx));

    string sRow = MW_QRow(sGuide, idx);
    SetCustomToken(7000, MW_Field(sRow, 0));

    // Fisher-Yates shuffle of answer indices {0,1,2,3}; answer 0 is the correct
    // one (field 1 of the row). Use PC scratch ints as a 4-slot array.
    int i;
    for (i = 0; i < MW_QUIZ_OPTS; i++)
        SetLocalInt(oPC, "mwperm" + IntToString(i), i);
    for (i = MW_QUIZ_OPTS - 1; i >= 1; i--)
    {
        int j  = Random(i + 1);
        int vi = GetLocalInt(oPC, "mwperm" + IntToString(i));
        int vj = GetLocalInt(oPC, "mwperm" + IntToString(j));
        SetLocalInt(oPC, "mwperm" + IntToString(i), vj);
        SetLocalInt(oPC, "mwperm" + IntToString(j), vi);
    }

    int nCor = 1;
    for (i = 0; i < MW_QUIZ_OPTS; i++)
    {
        int ai = GetLocalInt(oPC, "mwperm" + IntToString(i));
        SetCustomToken(7001 + i, MW_Field(sRow, ai + 1));   // fields 1..4 are answers
        if (ai == 0) nCor = i + 1;                          // slot holding the correct answer
        DeleteLocalInt(oPC, "mwperm" + IntToString(i));
    }
    SetLocalInt(oPC, "mw_" + sGuide + "_cor", nCor);

    int n = GetLocalInt(oPC, "mw_" + sGuide + "_n") + 1;
    SetLocalInt(oPC, "mw_" + sGuide + "_n", n);
    SetCustomToken(7005, "Question " + IntToString(n) + " of " + IntToString(MW_QUIZ_DRAW));
}

// Score the answer the PC just picked (slot 1..4).
void MW_QuizAnswer(object oPC, string sGuide, int nSlot)
{
    if (sGuide == "") return;
    if (nSlot == GetLocalInt(oPC, "mw_" + sGuide + "_cor"))
        SetLocalInt(oPC, "mw_" + sGuide + "_score",
                    GetLocalInt(oPC, "mw_" + sGuide + "_score") + 1);
}

// Score the pick, then draw the next question so its tokens are populated BEFORE
// the following entry renders. Loading on the answer reply (rather than on the
// question entry itself) is what keeps the displayed question aligned with the
// scored answer. After the final question (_n == MW_QUIZ_DRAW) there is nothing
// left to draw; the reply falls through to the pass/fail entry instead.
void MW_QuizAnswerNext(object oPC, string sGuide, int nSlot)
{
    MW_QuizAnswer(oPC, sGuide, nSlot);
    if (sGuide == "") return;
    if (GetLocalInt(oPC, "mw_" + sGuide + "_n") < MW_QUIZ_DRAW)
        MW_QuizLoad(oPC, sGuide);
}

// Pass check for the final branch (StartingConditional on the pass entry).
int MW_QuizPass(object oPC, string sGuide)
{
    return GetLocalInt(oPC, "mw_" + sGuide + "_score") >= MW_QUIZ_PASS;
}

// Clear all per-run state (called on unlock).
void MW_QuizClear(object oPC, string sGuide)
{
    DeleteLocalInt(oPC, "mw_" + sGuide + "_n");
    DeleteLocalInt(oPC, "mw_" + sGuide + "_score");
    DeleteLocalInt(oPC, "mw_" + sGuide + "_used");
    DeleteLocalInt(oPC, "mw_" + sGuide + "_cor");
}
