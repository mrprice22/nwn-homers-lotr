//::///////////////////////////////////////////////
//:: FileName sc_040
//:: Oliah the Mystic: this character already finished the quest.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

int StartingConditional()
{
    return QCD_TimesDone(GetPCSpeaker(), "mystic_heirloom_done") > 0;
}
