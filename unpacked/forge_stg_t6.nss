// Toggle the plan bit for staged disenchant menu slot 6 on the current page
// (absolute permanent-property index = FORGE_STG_PAGE * FORGE_DIS_SLOTS + 6),
// then re-prime the menu's per-slot cues + status header for the SAME page. The
// re-prime must happen here (a reply Actions Taken), before the D1 entry re-shows
// its text, so the [planned] marker and projected worth update on every click.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    ForgeStageToggleBit(oPC,
        GetLocalInt(oPC, "FORGE_STG_PAGE") * FORGE_DIS_SLOTS + 6);
    ForgeStageSetupCued(oPC, GetLocalObject(oPC, "MODIFY_ITEM"));
}
