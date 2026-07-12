// mw_q_a2 -- ActionTaken on the reply shown in slot 2: score it.
#include "mw_quiz_inc"
void main() { object oPC = GetPCSpeaker(); MW_QuizAnswer(oPC, GetLocalString(oPC, "mw_active"), 2); }
