// pl_optout_on - dialog conditional: show the "Opt back in" line only when the
// PC is currently opted out of party loot rolls.
#include "inc_partyloot"

int StartingConditional()
{
    return PL_IsOptedOut(GetPCSpeaker());
}
