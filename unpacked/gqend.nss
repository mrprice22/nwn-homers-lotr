//aldaron 13042004

#include "boost_inc"
void main()
{

object oPC = GetPCSpeaker();
SetLocalInt (oPC, "gquest", 2);

object FM = GetFirstFactionMember(oPC, TRUE);

while (GetIsObjectValid(FM))
{
 Boost_GiveXP (FM, 10000);
 FM = GetNextFactionMember (oPC, TRUE);
}

}
