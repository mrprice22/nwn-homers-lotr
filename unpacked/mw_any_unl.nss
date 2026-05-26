// mw_any_unl -- dialogue conditional: PC has unlocked at least one MeaningWave guide.
#include "mw_unlock_inc"
int StartingConditional() { return MW_UnlockCount(GetPCSpeaker()) >= 1; }
