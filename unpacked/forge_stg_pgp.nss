// "Show the previous enchantments" — step the staged disenchant menu back one
// page (clamped at the first) and re-prime the slot cues.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    int nPage = GetLocalInt(oPC, "FORGE_STG_PAGE") - 1;
    if (nPage < 0) nPage = 0;
    SetLocalInt(oPC, "FORGE_STG_PAGE", nPage);
    ForgeStageSetupCued(oPC, GetLocalObject(oPC, "MODIFY_ITEM"));
}
