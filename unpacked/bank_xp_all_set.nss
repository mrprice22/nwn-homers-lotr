#include "boost_inc"
void main()
{
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);
int iFamXP = GetCampaignInt("bankdb", "fam_xp_" + sCDKey);
Boost_GiveXPNoBoost(oPC, iFamXP);
SetCampaignInt("bankdb", "fam_xp_" + sCDKey, 0);
SetCustomToken(6002, "0");
}
