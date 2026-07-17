// q_dwd_c_prog -- TRUE while the stand is under way (stages 1-2):
// Halmir's reminder line. Listed after q_dwd_c_rdy on the branch, so it
// only shows when the turn-in line does not (no shard in hand yet, or
// the shard was lost -- the stone re-gives it).
// (roadmap: dwarven-defender-quest)
#include "q_dwd_inc"

int StartingConditional()
{
    int nStage = QDWD_GetStage(GetPCSpeaker());
    return nStage >= QDWD_STAGE_ACCEPTED && nStage <= QDWD_STAGE_SHARD;
}
