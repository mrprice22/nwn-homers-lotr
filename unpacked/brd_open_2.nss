// brd_open_2 - reply action: drill into the slain boss shown in row 2.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    BRD_BuildDetail(oPC, GetLocalString(oPC, "brd_slot_2"));
}
