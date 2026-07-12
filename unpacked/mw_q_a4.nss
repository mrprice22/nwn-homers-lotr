// mw_q_a4 -- ActionTaken on the reply shown in slot 4: score it.
#include "mw_quiz_inc"
void main() { object oPC = GetPCSpeaker(); MW_QuizAnswer(oPC, GetLocalString(oPC, "mw_active"), 4); }
