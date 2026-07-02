#include "boost_inc"
void main()
{
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);
int iNeeded = 3581000 - GetXP(oPC);
if(iNeeded <= 0) return;
int iFamXP = GetCampaignInt("bankdb", "fam_xp_" + sCDKey);
int iGive = iFamXP;
if(iGive > iNeeded) iGive = iNeeded;
Boost_GiveXPNoBoost(oPC, iGive);
SetCampaignInt("bankdb", "fam_xp_" + sCDKey, iFamXP - iGive);
SetCustomToken(6002, IntToString(GetCampaignInt("bankdb", "fam_xp_" + sCDKey)));
}
