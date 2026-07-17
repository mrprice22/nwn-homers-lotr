// q_bkg_start -- accept ActionTaken on Halmir's Blackguards branch
// (roadmap: blackguard-quest). Stage 0 -> 1 and journal entry 1. Nothing
// to spawn: the rite's objective is the existing torture-rack in the Keep
// of Barad-Dur (baraddurkeep.git.json, tag BkgFallAltar).
#include "q_bkg_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QBKG_GetStage(oPC) != QBKG_STAGE_NONE) return;

    QBKG_SetStage(oPC, QBKG_STAGE_ACCEPTED);
    AddJournalQuestEntry(QBKG_QUEST, 1, oPC, FALSE, FALSE);
}
