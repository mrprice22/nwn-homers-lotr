// mw_q_start -- ActionTaken on the "begin" reply: reset the quiz for this guide
// and draw the FIRST question, so its tokens are set before the question entry
// renders. The guide is derived from the NPC's tag (mw_<guide>_w).
#include "mw_quiz_inc"
void main()
{
    object oPC = GetPCSpeaker();
    string sGuide = MW_GuideFromTag();
    MW_QuizStart(oPC, sGuide);
    MW_QuizLoad(oPC, sGuide);
}
