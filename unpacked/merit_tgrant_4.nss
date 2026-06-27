// merit_tgrant_4 — Reply action: grant the tournament item in picker slot 4.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    string sResref = GetLocalString(oPC, "merit_tslot_4");
    if (sResref != "")
        Merit_GrantTournament(oPC, sResref, GetLocalString(oPC, "merit_tslot_4_name"));
}
