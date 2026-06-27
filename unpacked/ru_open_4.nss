// ru_open_4 — reply action: drill into the recent update shown in row 4.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    RU_BuildDetail(oPC, GetLocalInt(oPC, "ru_slot_4_rank"));
}
