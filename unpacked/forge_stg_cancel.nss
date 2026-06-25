// Abandon the disenchant plan: nothing was mutated, so the item is left whole
// and exactly as legal as it was before. Clear the staging plan and page.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    ForgeStageClear(oPC);
    DeleteLocalInt(oPC, "FORGE_STG_PAGE");
}
