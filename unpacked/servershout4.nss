void main()
{

object oPC = GetEnteringObject();

if (!GetIsPC(oPC)) return;

int DoOnce = GetLocalInt(oPC, GetTag(OBJECT_SELF));

if (DoOnce==TRUE) return;

SetLocalInt(oPC, GetTag(OBJECT_SELF), TRUE);

FloatingTextStringOnCreature("Join the discord at https://discord.gg/VpAtSpe - check the Announcements channel for recent updates and new codes you can use ingame for rewards!", oPC);
FloatingTextStringOnCreature("View the Wiki at homerslotrwiki.ddns.net  or  homers-lotr-wiki.jamesprice-slightlyepic.workers.dev", oPC);

}
