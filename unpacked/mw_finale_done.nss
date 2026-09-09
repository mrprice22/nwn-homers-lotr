// mw_finale_done -- dialogue conditional: PC already collected the mixtape.
#include "mw_unlock_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    MW_MigrateLegacy(oPC);
    return MW_GetFlag(oPC, "finale");
}
