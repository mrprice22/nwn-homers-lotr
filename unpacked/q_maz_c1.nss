// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// StartingConditional: TRUE while the PC is gathering seals (stage 1).
// Sets token 6380 to the PC's lit-brazier count for the progress line.
#include "q_maz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (MAZ_GetStage(oPC) != 1) return FALSE;
    SetCustomToken(6380, IntToString(MAZ_CountSeals(oPC)));
    return TRUE;
}
