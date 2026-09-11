// StartingConditional: is track slot 1 populated on the PC's current page?
#include "jb_inc"

int StartingConditional()
{
    return JB_SlotIndex(GetPCSpeaker(), 1) >= 0;
}
