//Notes from Loki: Implementation modified by LokiHakanin.
//Functions will now run on ANY PC entering the area, and will
//sort through all his gear in search of dupes.
//If one is found, it will be destroyed, and a logged entry
//will be made noting the time, item name, and player name.
//This message will also be sent to all DMs.

#include "zep_inc_craft"

void main()
{
  object oPC = GetEnteringObject();
  if (!GetIsObjectValid(oPC)) return;
  // Skip purification while a crafting session is active — TEMPITEM is
  // legitimately set on the item being worked on, and the session's own
  // cleanup (Abort / Make Changes) will clear it.  Purifying mid-session
  // quarantines the player's item out from under them.
  if (GetLocalInt(oPC, "ZEP_CR_STARTED")) return;
  ZEP_PurifyAllItems(oPC,TRUE,TRUE);
}
