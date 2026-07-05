// brd_open_0 — reply action: drill into the slain boss shown in row 0.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    BRD_BuildDetail(oPC, GetLocalString(oPC, "brd_slot_0"));
}
