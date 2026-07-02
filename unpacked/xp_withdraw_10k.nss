#include "xp_inc"
#include "boost_inc"

void main()
{
object oPC =GetPCSpeaker();
  if (WithdrawCap == TRUE)
   {
    if (GetXP(oPC) >= (XPcap - 9999))
     {
     SpeakString(slvlcap);
     return;
     }
   }
string sCDKey = GetPCPublicCDKey( oPC);
int fXP = GetCampaignInt( "XP", sCDKey) - 10000;

 SetCampaignInt( "XP", sCDKey, fXP);
 Boost_GiveXPNoBoost(oPC, 10000);
 SpeakString ("You have withrawn 10,000 XP.");
}
