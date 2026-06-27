// ru_open_3 — reply action: drill into the recent update shown in row 3.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    RU_BuildDetail(oPC, GetLocalInt(oPC, "ru_slot_3_rank"));
}
