int StartingConditional()
{
string sCDKey = GetPCPublicCDKey(GetPCSpeaker());
if(GetCampaignInt("bankdb", "fam_xp_" + sCDKey) < 100000) return 0;
if(GetXP(GetPCSpeaker()) + 100000 > 3581000) return 0;
return 1;
}
