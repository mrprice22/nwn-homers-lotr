// Hobbit Post (roadmap: hobbit-post)
// StartingConditional on recipient 3's accept entry: the PC carries a
// correctly-labelled parcel addressed to them.
#include "q_post_inc"

int StartingConditional()
{
    return QP_CanAccept(GetPCSpeaker(), 3);
}
