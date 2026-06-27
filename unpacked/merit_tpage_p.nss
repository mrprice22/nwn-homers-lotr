// merit_tpage_p — Reply action: previous page of tournament gear.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nOff = GetLocalInt(oPC, "merit_tpage_off") - 9;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oPC, "merit_tpage_off", nOff);
    Merit_BuildTournament(oPC);
}
