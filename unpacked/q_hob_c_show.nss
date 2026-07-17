// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the generic question entry: TRUE while a game is
// running and questions remain. Sets the entry-text tokens (6421 question
// number, 6422 question text) and records which displayed slot holds the
// correct answer. The four option tokens (6423-6426) are set per-reply by
// q_hob_c_o1..o4 (see QHOB_ShowOpt for why one-token-per-reply).
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_HOB_ACTIVE"))
        return FALSE;
    int nIdx = GetLocalInt(oPC, "Q_HOB_IDX");
    if (nIdx >= QHOB_ASKED)
        return FALSE;

    int nSeed = GetLocalInt(oPC, "Q_HOB_SEED");
    int nQ    = QHOB_QAt(nSeed, nIdx);
    int nRot  = (nSeed + nIdx) % 4;   // rotate answers so the letter moves

    SetCustomToken(6421, IntToString(nIdx + 1));
    SetCustomToken(6422, QHOB_Q(nQ));

    // Data option 0 (the correct one) lands on displayed slot nRot+1.
    SetLocalInt(oPC, "Q_HOB_SLOT", nRot + 1);
    return TRUE;
}
