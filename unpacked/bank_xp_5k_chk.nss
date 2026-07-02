int StartingConditional()
{
string sCDKey = GetPCPublicCDKey(GetPCSpeaker());
if(GetCampaignInt("bankdb", "fam_xp_" + sCDKey) < 5000) return 0;
if(GetXP(GetPCSpeaker()) + 5000 > 3581000) return 0;
return 1;
}
