// Action: play the track in slot 1 of the PC's current page, in this area.
#include "jb_inc"

void main()
{
    object oPC = GetPCSpeaker();
    int nIndex = JB_SlotIndex(oPC, 1);
    if (nIndex >= 0) JB_Start(GetArea(oPC), nIndex);
}
