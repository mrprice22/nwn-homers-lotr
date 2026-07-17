// q_sow_start -- fires on Ferny's instruction line (ferny_convo2) when
// the PC takes the Sowing Discord job: hands over the three forged
// letters (plot + cursed -- can't be dropped, sold or fed to a merchant)
// and opens the journal. Guarded against re-fires: never issues a second
// set while any letter is held, a plant awaits payment, or the daily
// cooldown is running. (roadmap: sowing-discord-bree)
#include "q_sow_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QSOW_InProgress(oPC)) return;
    if (QSOW_ReadyToTurnIn(oPC)) return;
    if (QCD_IsOnCooldown(oPC, QSOW_QUEST, QCD_DAY)) return;

    int i;
    for (i = 0; i < QSOW_LETTERS; i++)
        CreateItemOnObject(QSOW_LETTER_RES, oPC, 1);

    AddJournalQuestEntry(QSOW_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}
