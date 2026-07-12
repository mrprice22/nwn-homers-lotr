// mw_q_a1 -- ActionTaken on the reply shown in slot 1: score it, then draw the
// next question (so its tokens are set before the following entry renders).
#include "mw_quiz_inc"
void main() { object oPC = GetPCSpeaker(); MW_QuizAnswerNext(oPC, GetLocalString(oPC, "mw_active"), 1); }
