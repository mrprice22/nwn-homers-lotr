// prsg_c_bg.nss — hub line gate for the Blackguards
// (roadmap: prestige-trainer-hub). Shows Halmir's branch for this order
// only when the PC meets the order's minimum level (see prsg_inc.nss).
#include "prsg_inc"

int StartingConditional()
{
    return PRSG_MeetsLevel(GetPCSpeaker(), PRSG_LVL_BG);
}
