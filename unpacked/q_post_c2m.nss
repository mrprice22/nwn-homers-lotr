// Hobbit Post (roadmap: hobbit-post)
// StartingConditional on recipient 2's refusal entry: the parcel bears
// their name but was misdirected -- QP_IsMislabel sets tokens 6340/6341 to
// the true recipient so the line can point the player onward.
#include "q_post_inc"

int StartingConditional()
{
    return QP_IsMislabel(GetPCSpeaker(), 2);
}
