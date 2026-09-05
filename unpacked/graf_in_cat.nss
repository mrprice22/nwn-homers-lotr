// graf_in_cat.nss - StartingConditional: TRUE only on the third level of the
// browser, the list of looks. The single-step "next/previous look" rows are
// meaningless on the theme and category pages, so they only show here.
#include "graf_inc"
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "graf_mode") == 2;
}
