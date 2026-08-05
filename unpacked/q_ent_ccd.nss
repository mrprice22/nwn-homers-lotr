// The Thirteenth Ent (roadmap: thirteenth-ent)
// StartingConditional: qualified, but still inside the 24-real-hour wait
// after a failed (or spent) attempt. Fills token 6390 with the time left.
#include "q_ent_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (ENT_IsRestored(oPC)) return FALSE;

    int nLeft = 0;
    if (ENT_IsDruid(oPC))
        nLeft = QCD_SecondsRemaining(oPC, ENT_CD_DRUID, QCD_DAY);
    if (nLeft <= 0 && ENT_IsBard(oPC))
        nLeft = QCD_SecondsRemaining(oPC, ENT_CD_BARD, QCD_DAY);

    if (nLeft <= 0) return FALSE;

    SetCustomToken(ENT_TOKEN_CD, QCD_FmtSpan(nLeft));
    return TRUE;
}
