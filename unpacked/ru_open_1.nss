// ru_open_1 — reply action: drill into the recent update shown in row 1.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    RU_BuildDetail(oPC, GetLocalInt(oPC, "ru_slot_1_rank"));
}
