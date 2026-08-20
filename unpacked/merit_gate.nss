// merit_gate - StartingConditional: show the "redeem a reward" branch.
// TRUE on production for everyone, and for a whitelisted admin anywhere else.
// The inverse (merit_gate_no) shows the "shop is closed" branch instead, so the
// option never silently vanishes. The rule lives in sp_meritgate_inc.
#include "sp_meritgate_inc"

int StartingConditional()
{
    return SP_MeritShopFor(GetPCSpeaker());
}
