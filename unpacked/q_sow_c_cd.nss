// q_sow_c_cd -- StartingConditional for Ferny's "too hot right now"
// greeting (ferny_convo2): TRUE while the PC is on the Sowing Discord
// daily cooldown with nothing in flight. Registers token 6390 with the
// time left for "come back in <CUSTOM6390>". Same gates as the offer so
// Good PCs and under-levels just get ordinary Ferny.
// (roadmap: sowing-discord-bree)
#include "q_sow_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetHitDice(oPC) < QSOW_LEVEL) return FALSE;
    if (GetAlignmentGoodEvil(oPC) == ALIGNMENT_GOOD) return FALSE;
    if (QSOW_InProgress(oPC)) return FALSE;
    if (QSOW_ReadyToTurnIn(oPC)) return FALSE;
    if (!QCD_IsOnCooldown(oPC, QSOW_QUEST, QCD_DAY)) return FALSE;
    SetCustomToken(QSOW_TOKEN_CD,
        QCD_FmtSpan(QCD_SecondsRemaining(oPC, QSOW_QUEST, QCD_DAY)));
    return TRUE;
}
