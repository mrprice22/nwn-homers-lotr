// q_asn_c_st3 -- TRUE once the PC is counted among the quiet knives
// (stage 3+): Halmir's epilogue line. (roadmap: assassin-quest)
#include "q_asn_inc"

int StartingConditional()
{
    return QASN_GetStage(GetPCSpeaker()) >= QASN_STAGE_DONE;
}
