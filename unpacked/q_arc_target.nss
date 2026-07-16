// q_arc_target -- The Warden's Mark (roadmap: arcane-archer-quest).
// OnUsed of the old archery target on Rivendell's training ground
// (rivendell.git.json, existing placed instance reused -- retagged
// WardenMark, made usable; it had no previous OnUsed, so there is
// nothing to chain). Runs the Arcane Archers' trial for a PC on the
// rite:
//
//   * The come-as-an-archer fail condition: unless the PC stands with a
//     longbow or shortbow equipped AND arrows in the quiver
//     (QARC_ComesAsArcher), the attempt fails with a flavor message and
//     nothing is granted. Retry allowed -- string the bow, nock an
//     arrow, and use the mark again. Deterministic: no dice.
//   * As an archer at stage 1: gives the Warden's Shaft, stage 1 -> 2
//     + journal 2. At stage 2 with the shaft lost, re-gives it (never
//     duplicates -- GetItemPossessedBy guard; the item is plot + cursed
//     and only the finish consumes it).
//
// Does nothing for PCs not on the rite (a quiet flavor line only).
#include "q_arc_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QARC_GetStage(oPC);
    if (nStage < QARC_STAGE_ACCEPTED || nStage > QARC_STAGE_SHAFT)
    {
        FloatingTextStringOnCreature(
            "An old target, older than the house around it. Deep in the "
            + "gold ring sits a grey-fletched shaft no weather has touched.",
            oPC, FALSE);
        return;
    }
    if (QARC_HasShaft(oPC)) return;

    // The fail condition: come to the mark any way but an archer's way
    // and the shaft does not move. String the bow and try again.
    if (!QARC_ComesAsArcher(oPC))
    {
        FloatingTextStringOnCreature(
            "You set your hand to the grey-fletched shaft and it does not move -- "
            + "the mark does not know you. Come as an archer comes: bow in hand, "
            + "arrow nocked, quiver full.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QARC_SHAFT_RES, oPC, 1);

    if (nStage == QARC_STAGE_ACCEPTED)
    {
        QARC_SetStage(oPC, QARC_STAGE_SHAFT);
        AddJournalQuestEntry(QARC_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "With the bow in your hand the shaft comes free like a note leaving "
        + "a string -- grey-fletched, straight as the day it flew, and humming "
        + "faintly still.",
        oPC, FALSE);
}
