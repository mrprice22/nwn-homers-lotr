// graf_sum.nss - refresh the easel's "what you have chosen" token (6502).
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);          // keep the claim alive while they are talking
    Graf_Summary(oPC);
}
