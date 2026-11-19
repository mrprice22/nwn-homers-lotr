//::///////////////////////////////////////////////
//:: FileName at_066
//:: Oliah the Mystic: the PC agrees to put Anaralia to rest.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mystichelp", 1);
    if (QCD_TimesDone(oPC, "mystic_heirloom_accepted") == 0)
        QCD_Stamp(oPC, "mystic_heirloom_accepted");
}
