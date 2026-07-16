// prsg_c_dwdef.nss — hub line gate for the Dwarven Defenders (level gate + dwarf race)
// (roadmap: prestige-trainer-hub). Shows Halmir's branch for this order
// only when the PC meets the order's minimum level (see prsg_inc.nss).
#include "prsg_inc"

int StartingConditional()
{
    return PRSG_QualifiesDwarvenDef(GetPCSpeaker());
}
