// q_dwd_c_off -- Halmir's Dwarven Defenders branch: show the offer of
// the stand only to a PC who has not started the quest AND has already
// taken the Defender's stand (1+ Dwarven Defender level, and of Durin's
// folk -- the design gate). (roadmap: dwarven-defender-quest)
#include "q_dwd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QDWD_GetStage(oPC) == QDWD_STAGE_NONE
        && QDWD_IsDwarvenDefender(oPC);
}
