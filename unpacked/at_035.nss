//::///////////////////////////////////////////////
//:: FileName at_035
//:: King Theoden: the PC agrees to break the White Hand blockade.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "theodenq", 1);
    if (QCD_TimesDone(oPC, "theoden_blockade_accepted") == 0)
        QCD_Stamp(oPC, "theoden_blockade_accepted");
}
