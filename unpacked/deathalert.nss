#include "color"
#include "se_respawn_inc"

void main()
{
//Alerts which PC killed boss and where
object oBoss = OBJECT_SELF;
object oPC = GetLastHostileActor(oBoss);
object oArea = GetArea(oBoss);
string sBoss = GetName(oBoss);
string sPC = GetName(oPC);
string sArea = GetName(oArea);
object oPlayer = GetFirstPC();

// Standardized boss respawn: placed deathalert bosses (Thranduil, the Carn Dum
// Khamul) previously never respawned until reboot. Same 15-minute timer as all
// other placed creatures; encounter-spawned bosses (Balrog, Legolas, the Dol
// Guldur Khamul) are skipped inside SE_DoCreatureRespawn and come back via
// their encounter's ResetTime instead.
if (FindSubString(GetTag(oBoss), "NSP") == -1)
    SE_DoCreatureRespawn();

if (GetIsDead(oBoss))
     while (oPlayer != OBJECT_INVALID)
        {
        string sMessage = (sBoss + " was killed by "+sPC+" in <c�  > "+sArea + "</c>");
        SendMessageToPC(oPlayer, sMessage);
        oPlayer = GetNextPC();
        }

string tag = GetTag(OBJECT_SELF);

if (tag == "ADwarfAjudicator" || tag == "DunlandWarrior" || tag == "RivendellArcaneArcher" || tag == "RivendellWarrior")
{return;}

if(GetAlignmentGoodEvil(OBJECT_SELF) == ALIGNMENT_NEUTRAL){return;}

object oMod = GetModule();
string name = GetName(OBJECT_SELF); // or whatever to get the name of the dead NPC
if(GetAlignmentGoodEvil(OBJECT_SELF) == ALIGNMENT_GOOD)
{
string currentList = GetLocalString( oMod, "GoodNPCDeathList");
  if( currentList != "") currentList += "; ";
  currentList += name;
  SetLocalString( oMod, "GoodNPCDeathList", currentList);
}
else
{

string currentList = GetLocalString( oMod, "EvilNPCDeathList");
  if( currentList != "") currentList += "; ";
  currentList += name;
  SetLocalString( oMod, "EvilNPCDeathList", currentList);
}



}
