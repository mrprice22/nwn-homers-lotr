// StartingConditional: is track slot 5 populated on the PC's current page?
#include "jb_inc"

int StartingConditional()
{
    return JB_SlotIndex(GetPCSpeaker(), 5) >= 0;
}
