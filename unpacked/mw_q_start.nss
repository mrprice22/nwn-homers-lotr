// mw_q_start -- ActionTaken on the "begin" reply: reset the quiz for this guide.
// The guide is derived from the NPC's tag (mw_<guide>_w); the first question is
// loaded by the question entry's own mw_q_load, not here.
#include "mw_quiz_inc"
void main() { MW_QuizStart(GetPCSpeaker(), MW_GuideFromTag()); }
