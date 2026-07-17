// Pass the Pass (roadmap: pass-the-pass)
// StartingConditional on the quartermaster's turn-in line: TRUE when the PC is
// carrying an active escort to deliver.
#include "q_pass_inc"
int StartingConditional() { return QPASS_Active(GetPCSpeaker()); }
