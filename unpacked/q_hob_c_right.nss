// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the mid-game "right answer" entry: TRUE while the
// game is still running and the last answer was correct. Sets token 6427 to a
// rotating approving line. (The win/lose finale entries are checked first.)
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_HOB_ACTIVE")) return FALSE;
    if (!GetLocalInt(oPC, "Q_HOB_LAST"))   return FALSE;
    SetCustomToken(6427, QHOB_RightLine(GetLocalInt(oPC, "Q_HOB_IDX")));
    return TRUE;
}
