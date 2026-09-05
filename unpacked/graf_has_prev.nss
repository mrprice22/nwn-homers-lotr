// graf_has_prev.nss - StartingConditional for [<< Previous page].
#include "graf_inc"
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "graf_page_off") > 0;
}
