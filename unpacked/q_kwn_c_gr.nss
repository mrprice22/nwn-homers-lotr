// q_kwn_c_gr - gate guardsman: show the rally line only to a knight on
// the muster (stage 2) at a post not yet counted. Guards without a post
// index (q_kwn_post local int unset - e.g. future placements elsewhere)
// never offer it. (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    object oPC  = GetPCSpeaker();
    int    nPost = GetLocalInt(OBJECT_SELF, QKWN_POST_VAR);

    return nPost > 0
        && QKWN_GetStage(oPC) == QKWN_STAGE_MUSTER
        && !QKWN_HasPost(oPC, nPost);
}
