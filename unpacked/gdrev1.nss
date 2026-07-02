#include "boost_inc"
void main()
{
object oPC = GetPCSpeaker();

GiveXPToCreature (oPC, 500);
Boost_GiveGold (oPC, 1000);

SetLocalInt (oPC, "gdquest", 3);
AddJournalQuestEntry ("gdquest1", 2, oPC, TRUE, FALSE);
}
