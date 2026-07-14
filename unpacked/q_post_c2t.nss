// Hobbit Post (roadmap: hobbit-post)
// StartingConditional on recipient 2's bonus-accept entry: the parcel is
// mislabelled and they are its true recipient.
#include "q_post_inc"

int StartingConditional()
{
    return QP_IsTrue(GetPCSpeaker(), 2);
}
