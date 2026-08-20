// merit_gate_no - StartingConditional: show the "shop is closed here" branch.
// Exact inverse of merit_gate; both read the one predicate in sp_meritgate_inc
// so the two branches can never both show (or both hide).
#include "sp_meritgate_inc"

int StartingConditional()
{
    return !SP_MeritShopFor(GetPCSpeaker());
}
