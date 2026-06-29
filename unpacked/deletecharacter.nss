string RemoveCharFromString(string sName, string sChar)
{
//Lower case
string sLeft, sRight;
int nChar = FindSubString(sName, sChar);
int nLength= GetStringLength(sName);
while(nChar >= 0)
{

//Remove character from word
sRight = GetStringRight(sName, nLength-nChar-1);
sLeft = GetStringLeft (sName, nChar);

//Make new name minus the space
sName = sLeft + sRight;
nLength= GetStringLength(sName);
nChar = FindSubString(sName, sChar);
}
//return sName;
return sName;
}

void main()
{
object oPC = GetPCSpeaker();

string sUpperCase = RemoveCharFromString(GetName(oPC), " ");
string sCharName = GetStringLowerCase(sUpperCase);
string sPlayerName = GetPCPlayerName(oPC);
//backup
SetLocalString(oPC, "NWNX!SYSTEM!BACKUP", sPlayerName+"/"+sCharName+".bic");
//delete
DelayCommand(5.0, SetLocalString(oPC, "NWNX!SYSTEM!DELETE", "./servervault/"+sPlayerName+"/"+sCharName+".bic"));
DelayCommand(5.0, SendMessageToPC(oPC, "Character with name "+sCharName+" deleted"));
//boot after setting delete
DelayCommand(6.0, FloatingTextStringOnCreature("5 seconds", oPC, FALSE));
DelayCommand(7.0, FloatingTextStringOnCreature("4 seconds", oPC, FALSE));
DelayCommand(8.0, FloatingTextStringOnCreature("3 seconds", oPC, FALSE));
DelayCommand(9.0, FloatingTextStringOnCreature("2 seconds", oPC, FALSE));
DelayCommand(10.0, FloatingTextStringOnCreature("1 seconds", oPC, FALSE));
DelayCommand(11.0, FloatingTextStringOnCreature("Bootage!", oPC, FALSE));
DelayCommand(12.0,BootPC (oPC));
}
