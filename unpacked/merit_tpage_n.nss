// merit_tpage_n - Reply action: next page of tournament gear.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "merit_tpage_off", GetLocalInt(oPC, "merit_tpage_off") + 9);
    Merit_BuildTournament(oPC);
}
