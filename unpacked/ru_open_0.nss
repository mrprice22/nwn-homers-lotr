// ru_open_0 — reply action: drill into the recent update shown in row 0.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    RU_BuildDetail(oPC, GetLocalInt(oPC, "ru_slot_0_rank"));
}
