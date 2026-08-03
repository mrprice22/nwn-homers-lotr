// q_kwn_c_gd - gate guardsman: this post already stands mustered for the
// knight (stage 2, post counted). (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    object oPC  = GetPCSpeaker();
    int    nPost = GetLocalInt(OBJECT_SELF, QKWN_POST_VAR);

    return nPost > 0
        && QKWN_GetStage(oPC) == QKWN_STAGE_MUSTER
        && QKWN_HasPost(oPC, nPost);
}
