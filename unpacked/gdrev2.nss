#include "boost_inc"
void main()
{
object oPC = GetPCSpeaker();

Boost_GiveXP (oPC, 2000);
Boost_GiveGold (oPC, 4000);

SetLocalInt (oPC, "gdquest", 3);
AddJournalQuestEntry ("gdquest1", 2, oPC, TRUE, FALSE);
}
