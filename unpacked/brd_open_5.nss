// brd_open_5 — reply action: drill into the slain boss shown in row 5.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    BRD_BuildDetail(oPC, GetLocalString(oPC, "brd_slot_5"));
}
