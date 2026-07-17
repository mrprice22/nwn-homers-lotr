// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the generic riddle entry: TRUE while a game is
// running and riddles remain. Sets the entry-text tokens (6361 riddle number,
// 6362 verse) and records which displayed slot holds the correct answer.
//
// The four answer-option tokens (6363-6366) are NOT set here: setting all four
// in one loop left only the first-written token resolving in the reply list
// in-engine, so the distractor replies rendered empty and were suppressed.
// Each option token is now set by its own per-reply StartingConditional
// (q_rid_c_o1..o4 -> QRID_ShowOpt), one SetCustomToken per reply, immediately
// before that reply renders. Everything is derived from (week seed, riddle
// index), so re-showing the same riddle is idempotent.
#include "q_rid_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_RID_ACTIVE"))
        return FALSE;
    int nIdx = GetLocalInt(oPC, "Q_RID_IDX");
    if (nIdx >= QRID_ASKED)
        return FALSE;

    int nSeed = GetLocalInt(oPC, "Q_RID_SEED");
    int nRid  = QRID_RiddleAt(nSeed, nIdx);
    int nRot  = (nSeed + nIdx) % 4;   // rotate answers so the letter moves

    SetCustomToken(6361, IntToString(nIdx + 1));
    SetCustomToken(6362, QRID_Verse(nRid));

    // Data option 0 (the correct one) lands on displayed slot nRot+1.
    SetLocalInt(oPC, "Q_RID_SLOT", nRot + 1);
    return TRUE;
}
