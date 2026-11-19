//::///////////////////////////////////////////////
//:: FileName at_036
//:: King Theoden: turn in the White Hand Destroyer's scythe.
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"
#include "nw_i0_tool"

// The proof is the Destroyer's own scythe (whitehandscythe, tag
// WhiteHandScythe). It used to be the stock tag NW_WPLMSC004, which Tagget's
// store sells, so the boss could be skipped with a purchase.
//
// THEODEN_CHOICE unlocks exactly one of the item rewards (at_037/038/039),
// which the dialog reaches whether or not this script paid out.
void main()
{
    object oPC = GetPCSpeaker();
    DeleteLocalInt(oPC, "THEODEN_CHOICE");

    if (QCD_TimesDone(oPC, "theoden_blockade_done") > 0)
        return;

    // Anti-exploit: player can drop the proof item mid-conversation to keep it.
    object oItemToTake = GetItemPossessedBy(oPC, "WhiteHandScythe");
    if (!GetIsObjectValid(oItemToTake))
    {
        FloatingTextStringOnCreature(
            "You must have the proof in your possession.", oPC, FALSE);
        return;
    }

    DestroyObject(oItemToTake);
    QCD_Stamp(oPC, "theoden_blockade_done");
    SetLocalInt(oPC, "THEODEN_CHOICE", 1);
    RewardPartyGP(10000, oPC);
    RewardPartyXP(2000, oPC);
}
