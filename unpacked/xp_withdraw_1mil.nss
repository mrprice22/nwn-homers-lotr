 #include "xp_inc"
#include "boost_inc"

void main()
{
object oPC =GetPCSpeaker();
  if (WithdrawCap == TRUE)
   {
    if (GetXP(oPC) >= (XPcap - 999999))
     {
     SpeakString(slvlcap);
     return;
     }
   }
string sCDKey = GetPCPublicCDKey( oPC);;
int fXP = GetCampaignInt( "XP", sCDKey) -1000000;

 SetCampaignInt( "XP", sCDKey, fXP);
 Boost_GiveXPNoBoost(oPC, 1000000);
 SpeakString ("You have withdrawn 1,000,000 XP.");
}
