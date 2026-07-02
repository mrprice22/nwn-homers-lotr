#include "boost_inc"
void main()
{
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);
int iXP = 100000;
int iFamXP = GetCampaignInt("bankdb", "fam_xp_" + sCDKey);
Boost_GiveXPNoBoost(oPC, iXP);
SetCampaignInt("bankdb", "fam_xp_" + sCDKey, iFamXP - iXP);
SetCustomToken(6002, IntToString(GetCampaignInt("bankdb", "fam_xp_" + sCDKey)));
}
