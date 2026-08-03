// merit_tgrant_5 - Reply action: grant the tournament item in picker slot 5.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    string sResref = GetLocalString(oPC, "merit_tslot_5");
    if (sResref != "")
        Merit_GrantTournament(oPC, sResref, GetLocalString(oPC, "merit_tslot_5_name"));
}
