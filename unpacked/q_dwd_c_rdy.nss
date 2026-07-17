// q_dwd_c_rdy -- TRUE once the PC carries the shard at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: dwarven-defender-quest)
#include "q_dwd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QDWD_GetStage(oPC) == QDWD_STAGE_SHARD && QDWD_HasShard(oPC);
}
