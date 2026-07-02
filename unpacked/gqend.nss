//aldaron 13042004

void main()
{

object oPC = GetPCSpeaker();
SetLocalInt (oPC, "gquest", 2);

object FM = GetFirstFactionMember(oPC, TRUE);

while (GetIsObjectValid(FM))
{
 GiveXPToCreature (FM, 10000);
 FM = GetNextFactionMember (oPC, TRUE);
}

}
