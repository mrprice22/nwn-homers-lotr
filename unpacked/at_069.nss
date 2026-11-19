//::///////////////////////////////////////////////
//:: FileName at_069
//:: Oliah the Mystic: turn in Anaralia's Eye (reply action, runs before at_068).
//::
//:: Quest state is per character in questcddb (quest_cd_inc) - a local int
//:: cleared on every reboot and made the reward farmable
//:: (roadmap: mystic-theoden-quest-state).
//:://////////////////////////////////////////////
#include "quest_cd_inc"

// The take, the possession re-check and the once-per-character stamp all
// happen HERE. at_068 (the next entry) only pays when this script hands it
// MYSTIC_PAID - otherwise dropping the eye before clicking paid out and kept
// the eye.
void main()
{
    object oPC = GetPCSpeaker();
    DeleteLocalInt(oPC, "MYSTIC_PAID");

    if (QCD_TimesDone(oPC, "mystic_heirloom_done") > 0)
        return;

    object oEye = GetItemPossessedBy(oPC, "AnaraliasEye");
    if (!GetIsObjectValid(oEye))
    {
        FloatingTextStringOnCreature(
            "You must have Anaralia's Eye in your possession.", oPC, FALSE);
        return;
    }

    DestroyObject(oEye);
    QCD_Stamp(oPC, "mystic_heirloom_done");
    SetLocalInt(oPC, "MYSTIC_PAID", 1);
}
