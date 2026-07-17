// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on answer reply slot 3 (token 6425). Always visible
// while a question is on offer; its one job is to set THIS slot's option token
// right before the reply renders (see QHOB_ShowOpt for why one-token-per-reply).
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "Q_HOB_ACTIVE")) return FALSE;
    if (GetLocalInt(oPC, "Q_HOB_IDX") >= QHOB_ASKED) return FALSE;
    QHOB_ShowOpt(oPC, 3);
    return TRUE;
}
