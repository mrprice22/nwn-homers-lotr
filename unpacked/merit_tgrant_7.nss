// merit_tgrant_7 - Reply action: grant the tournament item in picker slot 7.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    string sResref = GetLocalString(oPC, "merit_tslot_7");
    if (sResref != "")
        Merit_GrantTournament(oPC, sResref, GetLocalString(oPC, "merit_tslot_7_name"));
}
