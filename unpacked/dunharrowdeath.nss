#include "color"
#include "se_respawn_inc"

void main()
{
// Standardized boss respawn: the Heir of Haldor previously never respawned
// until reboot. Same 15-minute timer as all other placed creatures.
if (FindSubString(GetTag(OBJECT_SELF), "NSP") == -1)
    SE_DoCreatureRespawn();

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
        string sMessage = (sBoss + " was killed by "+sPC+" in <c���> "+sArea + "</c>");
        SendMessageToPC(oPlayer, sMessage);
        oPlayer = GetNextPC();
        }
string sResRef = "dunharrowdoor";
object oPortal = GetWaypointByTag("WP_kingdoor");
location lPortal = GetLocation(oPortal);
CreateObject(OBJECT_TYPE_PLACEABLE, sResRef, lPortal, TRUE);
 effect eVis = EffectVisualEffect(286);
  ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oPC);

// Paths of the Dead: laying the King of the Dead to rest completes the quest.
if (GetIsPC(oPC) && GetCampaignInt("potd", "started", oPC))
    AddJournalQuestEntry("paths_of_the_dead", 50, oPC, FALSE, FALSE);
}
