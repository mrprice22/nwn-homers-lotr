// prsg_c_rdd.nss — hub line gate for the Red Dragon Disciples
// (roadmap: prestige-trainer-hub). Shows Halmir's branch for this order
// only when the PC meets the order's minimum level (see prsg_inc.nss).
#include "prsg_inc"

int StartingConditional()
{
    return PRSG_MeetsLevel(GetPCSpeaker(), PRSG_LVL_RDD);
}
