// q_asn_drop -- the assassins' dead drop (roadmap: assassin-quest).
// OnOpen of the old wine barrel standing against the houses of Bree
// (bree.git.json, existing placed instance 112 of barrel001 reused --
// retagged AsnDeadDrop; it was already usable and Plot with no previous
// OnOpen/OnUsed, so there is nothing to chain and it cannot be bashed
// away). Runs the quiet knives' trial for a PC on the rite:
//
//   * The no-eye-marks-the-hand fail condition: if the PC opens the
//     barrel while NOT in stealth mode (QASN_IsUnseen, GetActionMode /
//     ACTION_MODE_STEALTH) the attempt fails with a flavor message and
//     nothing is granted. Retry allowed -- step into shadow, enter
//     stealth, and open the barrel again. Deterministic: the toggled
//     mode is the test, no dice and no skill roll.
//   * Unseen at stage 1: gives the Sealed Writ, stage 1 -> 2 + journal 2.
//     At stage 2 with the writ lost, re-gives it (never duplicates --
//     GetItemPossessedBy guard; the item is plot + cursed and only the
//     finish consumes it).
//
// Does nothing for PCs not on the rite -- to everyone else this is just
// an empty wine barrel, which is the point of a dead drop.
#include "q_asn_inc"

void main()
{
    object oPC = GetLastOpenedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QASN_GetStage(oPC);
    if (nStage < QASN_STAGE_ACCEPTED || nStage > QASN_STAGE_WRIT) return;
    if (QASN_HasWrit(oPC)) return;

    // The fail condition: come to the drop openly and it is only a
    // barrel. No eye may be able to mark the hand that lifts the writ.
    if (!QASN_IsUnseen(oPC))
    {
        FloatingTextStringOnCreature(
            "The barrel holds rainwater and a smell of old wine -- nothing "
            + "more. You came to it openly, and a dead drop yields nothing "
            + "to a hand any eye could mark. Slip into shadow, move unseen, "
            + "and reach in again.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QASN_WRIT_RES, oPC, 1);

    if (nStage == QASN_STAGE_ACCEPTED)
    {
        QASN_SetStage(oPC, QASN_STAGE_WRIT);
        AddJournalQuestEntry(QASN_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "Your fingers find a fold of grey paper pressed beneath the "
        + "barrel's rim, closed with black wax and no sigil. No one saw "
        + "your hand. No one ever does. Carry it to Halmir sealed.",
        oPC, FALSE);
}
