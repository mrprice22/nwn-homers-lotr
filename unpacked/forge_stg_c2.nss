// Page-aware count gate for staged-menu slot 2: show the slot only when its
// absolute property index (page * FORGE_DIS_SLOTS + 2) is within the item's
// permanent-property count.
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "FORGE_STG_PAGE") * FORGE_DIS_SLOTS + 2)
        < GetLocalInt(oPC, "FORGE_DIS_COUNT");
}
