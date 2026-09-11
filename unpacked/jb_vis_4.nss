// StartingConditional: is track slot 4 populated on the PC's current page?
#include "jb_inc"

int StartingConditional()
{
    return JB_SlotIndex(GetPCSpeaker(), 4) >= 0;
}
