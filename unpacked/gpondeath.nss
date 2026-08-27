#include "boost_inc"
#include "se_respawn_inc"
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

// Bring the creature back on the standard 15-minute timer, like every other
// OnDeath in the module. XP/gold above is already correct (pwfxp), so this
// must NOT delegate to nw_c2_default7 -- that would run party_xp on top.
if (FindSubString(GetTag(OBJECT_SELF), "NSP") == -1)
    SE_DoCreatureRespawn();
}
