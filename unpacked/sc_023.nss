//::///////////////////////////////////////////////
//:: FileName sc_023
//:: King Theoden: this character already broke the blockade.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

int StartingConditional()
{
    return QCD_TimesDone(GetPCSpeaker(), "theoden_blockade_done") > 0;
}
