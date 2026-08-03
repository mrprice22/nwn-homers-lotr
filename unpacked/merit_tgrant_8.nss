// merit_tgrant_8 - Reply action: grant the tournament item in picker slot 8.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    string sResref = GetLocalString(oPC, "merit_tslot_8");
    if (sResref != "")
        Merit_GrantTournament(oPC, sResref, GetLocalString(oPC, "merit_tslot_8_name"));
}
