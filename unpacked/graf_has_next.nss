// graf_has_next.nss - StartingConditional for [Next page >>].
#include "graf_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "graf_page_off") + GRAF_PAGE)
            < GetLocalInt(oPC, "graf_page_total");
}
