// pl_is_leader — dialog conditional: show party-leader-only loot options only
// when the speaking PC is their faction's leader (a solo PC is their own leader).
#include "inc_partyloot"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetFactionLeader(oPC) == oPC;
}
