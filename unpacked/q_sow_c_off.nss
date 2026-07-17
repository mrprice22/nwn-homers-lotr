// q_sow_c_off -- StartingConditional for Bill Ferny's "Sowing Discord"
// offer greeting (ferny_convo2). Shows only to a PC of total level 15+
// who is not Good-aligned (Good PCs never hear the whisper), with no job
// in flight (no letters held, nothing planted awaiting payment) and the
// daily cooldown clear. (roadmap: sowing-discord-bree)
#include "q_sow_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetHitDice(oPC) < QSOW_LEVEL) return FALSE;
    if (GetAlignmentGoodEvil(oPC) == ALIGNMENT_GOOD) return FALSE;
    if (QSOW_InProgress(oPC)) return FALSE;
    if (QSOW_ReadyToTurnIn(oPC)) return FALSE;
    if (QCD_IsOnCooldown(oPC, QSOW_QUEST, QCD_DAY)) return FALSE;
    return TRUE;
}
