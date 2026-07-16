// q_pal_tomb -- The Twenty-First Tomb (roadmap: pale-master-quest).
// OnOpen of the unmarked sarcophagus instance in the Bree Crypt Lower
// Level (breecryptlowerle.git.json, existing placed "Coffin" reused).
// Keeps the instance's previous OnOpen (nw_o2_classhig, treasure
// generation) by chaining it, then hands the pale grave-dust to a PC on
// the rite: stage 1 -> 2 + journal 2, or a re-give at stage 2 if the
// dust was somehow lost. Never duplicates the dust (GetItemPossessedBy
// guard) and does nothing for PCs not on the rite.
#include "q_pal_inc"

void main()
{
    // Treasure generation (the instance's previous OnOpen), unchanged.
    ExecuteScript("nw_o2_classhig", OBJECT_SELF);

    object oPC = GetLastOpenedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QPAL_GetStage(oPC);
    if (nStage < QPAL_STAGE_ACCEPTED || nStage > QPAL_STAGE_DUST) return;
    if (QPAL_HasDust(oPC)) return;

    CreateItemOnObject(QPAL_DUST_RES, oPC, 1);

    if (nStage == QPAL_STAGE_ACCEPTED)
    {
        QPAL_SetStage(oPC, QPAL_STAGE_DUST);
        AddJournalQuestEntry(QPAL_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "Beneath the unmarked lid lies only pale dust. You take a measure, unspilled.",
        oPC, FALSE);
}
