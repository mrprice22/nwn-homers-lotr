// mw_q_load -- ActionTaken on each question entry: draw the next random question
// and populate the answer tokens (7000-7005) just before the node renders.
#include "mw_quiz_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_QuizLoad(oPC, GetLocalString(oPC, "mw_active"));
}
