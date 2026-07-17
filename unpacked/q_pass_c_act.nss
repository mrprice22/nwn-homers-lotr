// Pass the Pass (roadmap: pass-the-pass)
// StartingConditional on the giver's "get the caravan moving" reminder line:
// TRUE while an escort is already in progress (accepted but not yet delivered).
#include "q_pass_inc"
int StartingConditional() { return QPASS_Active(GetPCSpeaker()); }
