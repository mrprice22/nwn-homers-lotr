// StartingConditional: is track slot 3 populated on the PC's current page?
#include "jb_inc"

int StartingConditional()
{
    return JB_SlotIndex(GetPCSpeaker(), 3) >= 0;
}
