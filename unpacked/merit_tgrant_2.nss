// merit_tgrant_2 - Reply action: grant the tournament item in picker slot 2.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    string sResref = GetLocalString(oPC, "merit_tslot_2");
    if (sResref != "")
        Merit_GrantTournament(oPC, sResref, GetLocalString(oPC, "merit_tslot_2_name"));
}
