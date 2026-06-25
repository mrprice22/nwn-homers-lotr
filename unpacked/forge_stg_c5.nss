// Page-aware count gate for staged-menu slot 5: show the slot only when its
// absolute property index (page * FORGE_DIS_SLOTS + 5) is within the item's
// permanent-property count. Separate from the Warden's non-paginated forge_dis_c*
// gates so the immediate-removal jail menu is unaffected.
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "FORGE_STG_PAGE") * FORGE_DIS_SLOTS + 5)
        < GetLocalInt(oPC, "FORGE_DIS_COUNT");
}
