#include "boost_inc"
void main()
{
object oKiller = GetLastKiller();
float CR = GetChallengeRating(OBJECT_SELF);
int iCR = FloatToInt(CR);
int iGP = (iCR * 8) + d20();
Boost_GiveGold(oKiller, iGP);
// pwfxp grants XP; the 2x is applied centrally by boost_xp_evt (NWNX SetExperience).
ExecuteScript("pwfxp",OBJECT_SELF);
int iRace = GetRacialType(OBJECT_SELF);
if (iRace == RACIAL_TYPE_ANIMAL  || iRace == RACIAL_TYPE_BEAST || iRace == RACIAL_TYPE_DRAGON)
 {
 ExecuteScript("trade_death",OBJECT_SELF);
 }
}
