// ru_open_2 — reply action: drill into the recent update shown in row 2.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    RU_BuildDetail(oPC, GetLocalInt(oPC, "ru_slot_2_rank"));
}
