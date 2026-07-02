int StartingConditional()
{
string sCDKey = GetPCPublicCDKey(GetPCSpeaker());
int iBankXP = GetCampaignInt("bankdb", "fam_xp_" + sCDKey);
if(iBankXP < 1) return 0;
if(GetXP(GetPCSpeaker()) + iBankXP > 3581000) return 0;
return 1;
}
