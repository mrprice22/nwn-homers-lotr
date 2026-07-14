// Hobbit Post (roadmap: hobbit-post)
// ActionTaken on every accepting recipient entry (normal delivery and the
// true recipient of a mislabelled parcel). All logic lives in QP_Pay.
#include "q_post_inc"

void main()
{
    QP_Pay(GetPCSpeaker());
}
