// StartingConditional: is there a page before this one?
#include "jb_inc"

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "jb_hasprev");
}
