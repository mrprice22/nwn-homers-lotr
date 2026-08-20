// bank_box_hasbox.nss - StartingConditional: is the PC carrying a strongbox?
//
// Scans all five box indices, like bank_fam_hasbox does. It used to test only
// the highest index (the account size), so a player with a 3-box account who was
// carrying boxes 1-2 but not 3 read as "no box" and dropped through to the
// normal greeting - which, before the open scripts were made idempotent, was the
// personal-vault half of the duplication exploit
// (roadmap banking-duplicate-exploit).
//
// NOTE: the illegal-item purge below is load-bearing side-effect code. This
// conditional sits on the banker's StartingList, so it runs on every banker
// conversation start; that is what sweeps the listed banned items out of player
// inventories. Do not move or drop it.

int StartingConditional()
{
int iFlag = 0;
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);

int iCounter = 1;
while(iCounter <= 5)
   {
   if(GetItemPossessedBy(oPC, "az_strongbox_" + sCDKey + "_" + IntToString(iCounter)) != OBJECT_INVALID)
      {
      iFlag = 1;
      break;
      }
   iCounter = iCounter + 1;
   }

    object oDupe = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oDupe ))
    {
         if(GetTag(oDupe) == "ChosenFist" ||GetTag(oDupe) ==  "ChickyChickyGauntlet" ||GetTag(oDupe) ==  "EpicGauntletofGollum" ||GetTag(oDupe) ==  "Glamdring" ||GetTag(oDupe) ==  "Glamdring3" ||GetTag(oDupe) ==  "DMsHelper")
         {
                DestroyObject(oDupe);
                WriteTimestampedLogEntry("ILLEGAL ITEM (" + GetTag(oDupe) + " - " + GetPCPlayerName(oPC) + " [" + GetPCPublicCDKey(oPC) + "]");
         }
         oDupe = GetNextItemInInventory(oPC);
    }

    // Glamdring
    // Glamdring3
    // ChosenFist
    // EpicGauntletofGollum
    // DMsHelper

return iFlag;
}
