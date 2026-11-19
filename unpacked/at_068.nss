//::///////////////////////////////////////////////
//:: FileName at_068
//:: Oliah the Mystic: the reward. Pays only after a verified turn-in in at_069.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetLocalInt(oPC, "MYSTIC_PAID"))
        return;
    DeleteLocalInt(oPC, "MYSTIC_PAID");

    GiveGoldToCreature(oPC, 100000);
    CreateItemOnObject("themysticheirloo", oPC, 1);
}
