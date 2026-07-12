// mw_q_pass -- StartingConditional on the pass entry: did the PC pass this run?
#include "mw_quiz_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return MW_QuizPass(oPC, GetLocalString(oPC, "mw_active"));
}
