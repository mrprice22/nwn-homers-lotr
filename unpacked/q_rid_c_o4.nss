// The Riddle Game (roadmap: riddle-game)
// StartingConditional on answer reply slot 4 (token 6366). Always visible while
// a riddle is on offer; sets THIS slot's option token right before the reply
// renders (see QRID_ShowOpt for why one-token-per-reply).
#include "q_rid_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_RID_ACTIVE")) return FALSE;
    if (GetLocalInt(oPC, "Q_RID_IDX") >= QRID_ASKED) return FALSE;
    QRID_ShowOpt(oPC, 4);
    return TRUE;
}
