// mw_q_unlock -- ActionTaken on the pass entry: unlock the guide and clear state.
#include "mw_quiz_inc"
void main()
{
    object oPC = GetPCSpeaker();
    string sGuide = GetLocalString(oPC, "mw_active");
    MW_Unlock(oPC, sGuide);
    MW_QuizClear(oPC, sGuide);
}
