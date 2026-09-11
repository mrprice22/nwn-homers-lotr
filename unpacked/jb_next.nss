// StartingConditional: is there a page after this one?
#include "jb_inc"

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "jb_hasnext");
}
