#include "boost_inc"
void main()
{
object oPC = GetPCSpeaker();

GiveXPToCreature (oPC, 4000);
Boost_GiveGold (oPC, 8000);

SetLocalInt (oPC, "gdquest", 3);
AddJournalQuestEntry ("gdquest1", 2, oPC, TRUE, FALSE);
}
