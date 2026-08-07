// Pick disenchant slot 2 and stage its name in token 6118 for the confirm.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "FORGE_DIS_PICK", 2);
    SetCustomToken(6118, ForgeSlotLabel(ForgeGetPropByIndexSel(
        GetLocalObject(oPC, "FORGE_DIS_ITEM"), 2, FORGE_SEL_REMOVABLE)));
}
