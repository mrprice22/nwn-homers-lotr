//::///////////////////////////////////////////////
//:: FileName sc_020
//:: King Theoden: blockade quest accepted and not yet finished.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (QCD_TimesDone(oPC, "theoden_blockade_done") > 0)
        return FALSE;
    return GetLocalInt(oPC, "theodenq") == 1
        || QCD_TimesDone(oPC, "theoden_blockade_accepted") > 0;
}
