// brd_open_1 — reply action: drill into the slain boss shown in row 1.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    BRD_BuildDetail(oPC, GetLocalString(oPC, "brd_slot_1"));
}
