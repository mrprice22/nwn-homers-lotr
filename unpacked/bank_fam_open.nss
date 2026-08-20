// bank_fam_open.nss - hand out the player's family strongboxes
//
// The retrieve is per-index idempotent: if the PC is already carrying family box
// N (because a previous vault session was broken off with ESC, or because the
// dialog looped back to this reply), we do NOT retrieve a second copy. Doing so
// used to duplicate items - RetrieveCampaignObject does not clear or lock the DB
// row, so re-opening spawned another box loaded from the unchanged snapshot
// while the emptied one was still in the pack (roadmap banking-duplicate-exploit).

#include "bank_box_inc"

void main()
{
object oPC = GetPCSpeaker();
string sCDKey = GetPCPublicCDKey(oPC);
object oVault = GetNearestObjectByTag("pl_vaultstorage");
int iBoxNum = GetCampaignInt("bankdb", "fam_account_" + sCDKey);
int iCounter = 1;
int nOpened = 0;
while(iCounter <= iBoxNum)
   {
   string sBoxTag = "az_familybox_" + sCDKey + "_" + IntToString(iCounter);
   if(!GetIsObjectValid(GetItemPossessedBy(oPC, sBoxTag)))
      {
      RetrieveCampaignObject("bankdb", "fam_box_" + sCDKey + "_" + IntToString(iCounter), GetLocation(oVault), oPC);
      if(GetIsObjectValid(GetItemPossessedBy(oPC, sBoxTag)))
         nOpened = nOpened + 1;
      }
   iCounter = iCounter + 1;
   }
Bank_LogOpen(oPC, "family", iBoxNum, nOpened, "open_family");
}
