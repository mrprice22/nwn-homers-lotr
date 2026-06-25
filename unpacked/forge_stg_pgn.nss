// "Show more enchantments" — advance the staged disenchant menu to the next page
// and re-prime the slot cues. The menu re-shows via the D1 entry (child link).
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "FORGE_STG_PAGE", GetLocalInt(oPC, "FORGE_STG_PAGE") + 1);
    ForgeStageSetupCued(oPC, GetLocalObject(oPC, "MODIFY_ITEM"));
}
