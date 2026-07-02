#include "boost_inc"
void main()
{
object oKiller = GetLastKiller();
float CR = GetChallengeRating(OBJECT_SELF);
int iCR = FloatToInt(CR);
int iGP = (iCR * 8) + d20();
Boost_GiveGold(oKiller, iGP);
// pwfxp (XP grant) lives in a hak; snapshot/top-up for the 2x boost.
Boost_SnapshotPartyXP(oKiller);
ExecuteScript("pwfxp",OBJECT_SELF);
Boost_TopupPartyXP(oKiller);
int iRace = GetRacialType(OBJECT_SELF);
if (iRace == RACIAL_TYPE_ANIMAL  || iRace == RACIAL_TYPE_BEAST || iRace == RACIAL_TYPE_DRAGON)
 {
 ExecuteScript("trade_death",OBJECT_SELF);
 }
}
