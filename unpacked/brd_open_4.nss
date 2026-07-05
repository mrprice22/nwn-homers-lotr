// brd_open_4 — reply action: drill into the slain boss shown in row 4.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    BRD_BuildDetail(oPC, GetLocalString(oPC, "brd_slot_4"));
}
