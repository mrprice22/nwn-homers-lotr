// Show the "more enchantments" reply only when a further page of properties
// exists beyond the current one (page+1 worth of slots is within the count).
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "FORGE_STG_PAGE") + 1) * FORGE_DIS_SLOTS
        < GetLocalInt(oPC, "FORGE_DIS_COUNT");
}
