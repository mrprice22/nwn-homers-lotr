// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the generic riddle entry: TRUE while a game is
// running and riddles remain. Sets the display tokens (6361 riddle number,
// 6362 verse, 6363-6366 the four answer options) and records which
// displayed slot holds the correct answer. Everything is derived from
// (week seed, riddle index), so re-showing the same riddle is idempotent.
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
    int j;
    for (j = 0; j < 4; j++)
        SetCustomToken(6363 + ((j + nRot) % 4), QRID_Opt(nRid, j));

    // Data option 0 (the correct one) landed on displayed slot nRot+1.
    SetLocalInt(oPC, "Q_RID_SLOT", nRot + 1);
    return TRUE;
}
