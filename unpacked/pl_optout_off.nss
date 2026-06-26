// pl_optout_off — dialog conditional: show the "Opt out" line only when the PC
// is currently participating in party loot rolls.
#include "inc_partyloot"

int StartingConditional()
{
    return !PL_IsOptedOut(GetPCSpeaker());
}
