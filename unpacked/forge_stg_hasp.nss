// Show the "previous enchantments" reply only when not on the first page.
#include "forge_inc"

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "FORGE_STG_PAGE") > 0;
}
