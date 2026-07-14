// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the mid-game "right answer" entry: TRUE while the
// game is still running and the last answer was correct. Sets token 6367 to
// a rotating grudging-praise gollum-ism. (The win/lose finale entries are
// checked before this one in the dialogue.)
#include "q_rid_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_RID_ACTIVE")) return FALSE;
    if (!GetLocalInt(oPC, "Q_RID_LAST"))   return FALSE;
    SetCustomToken(6367, QRID_RightQuip(GetLocalInt(oPC, "Q_RID_IDX")));
    return TRUE;
}
