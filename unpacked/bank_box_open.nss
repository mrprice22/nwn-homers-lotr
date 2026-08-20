// bank_box_open.nss - hand out the player's personal strongboxes
//
// Per-index idempotent, for the same reason as bank_fam_open: re-opening a vault
// the PC is still carrying used to mint a second same-tagged box from the
// unchanged DB snapshot, duplicating its contents
// (roadmap banking-duplicate-exploit).

#include "bank_box_inc"

void main()
{
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);
object oVault = GetNearestObjectByTag("pl_vaultstorage");
int iBoxNum = GetCampaignInt("bankdb", "bank_account", oPC);
int iCounter = 1;
int nOpened = 0;
while(iCounter <= iBoxNum)
   {
   string sBoxTag = "az_strongbox_" + sCDKey + "_" + IntToString(iCounter);
   if(!GetIsObjectValid(GetItemPossessedBy(oPC, sBoxTag)))
      {
      RetrieveCampaignObject("bankdb", "bank_box_" + IntToString(iCounter), GetLocation(oVault), oPC, oPC);
      if(GetIsObjectValid(GetItemPossessedBy(oPC, sBoxTag)))
         nOpened = nOpened + 1;
      }
   iCounter = iCounter + 1;
   }
Bank_LogOpen(oPC, "strong", iBoxNum, nOpened, "open_strong");
}
