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
if (GetIsDead(oBoss))
     while (oPlayer != OBJECT_INVALID)
        {
        string sMessage = (sBoss + " was killed by "+sPC+" in <c�  > "+sArea + "</c>");
        SendMessageToPC(oPlayer, sMessage);
        oPlayer = GetNextPC();
        }

object oMod = GetModule();
string name = GetName(OBJECT_SELF);

string currentList = GetLocalString( oMod, "EvilNPCDeathList");
  if( currentList != "") currentList += "; ";
  currentList += name;
  SetLocalString( oMod, "EvilNPCDeathList", currentList);

SpeakString("Dol Guldur is under attack! Rally Servants of Sauron to Dol Guldur!", TALKVOLUME_SHOUT);

// Respawn this boss 15 min after death (feeds the Roll of the Fallen board).
if (FindSubString(GetTag(OBJECT_SELF), "NSP") == -1)
    SE_DoCreatureRespawn();
}
