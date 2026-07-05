// brd_open_3 — reply action: drill into the slain boss shown in row 3.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    BRD_BuildDetail(oPC, GetLocalString(oPC, "brd_slot_3"));
}
