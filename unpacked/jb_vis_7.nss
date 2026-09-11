// StartingConditional: is track slot 7 populated on the PC's current page?
#include "jb_inc"

int StartingConditional()
{
    return JB_SlotIndex(GetPCSpeaker(), 7) >= 0;
}
