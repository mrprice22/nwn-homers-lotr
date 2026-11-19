//::///////////////////////////////////////////////
//:: FileName sc_039
//:: Oliah the Mystic: quest accepted and not yet finished.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (QCD_TimesDone(oPC, "mystic_heirloom_done") > 0)
        return FALSE;
    return GetLocalInt(oPC, "mystichelp") == 1
        || QCD_TimesDone(oPC, "mystic_heirloom_accepted") > 0;
}
