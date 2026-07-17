// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the mid-game "wrong answer" entry: TRUE while the
// game is still running and the last answer was wrong. Sets token 6428 to a
// rotating corrective line.
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_HOB_ACTIVE")) return FALSE;
    if (GetLocalInt(oPC, "Q_HOB_LAST"))    return FALSE;
    SetCustomToken(6428, QHOB_WrongLine(GetLocalInt(oPC, "Q_HOB_IDX")));
    return TRUE;
}
