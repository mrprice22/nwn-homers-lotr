// Beorn's Garden (roadmap: beorns-garden)
// StartingConditional on the turn-in reply: TRUE when the PC carries a full
// day's pelts AND has harvested all three hives.
#include "q_brn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return BRN_CountPelts(oPC) >= BRN_NEED_PELTS
        && BRN_CountHoney(oPC) >= BRN_NEED_HONEY;
}
