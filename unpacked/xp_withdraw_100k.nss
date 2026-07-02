       #include "xp_inc"
#include "boost_inc"

void main()
{
object oPC =GetPCSpeaker();
  if (WithdrawCap == TRUE)
   {
    if (GetXP(oPC) >= (XPcap - 99999))
     {
     SpeakString(slvlcap);
     return;
     }
   }
string sCDKey = GetPCPublicCDKey( oPC);
int fXP = GetCampaignInt( "XP", sCDKey) - 100000;

 SetCampaignInt( "XP", sCDKey, fXP);
 Boost_GiveXPNoBoost(oPC, 100000);
 SpeakString ("You have withrawn 100,000 XP.");
}
