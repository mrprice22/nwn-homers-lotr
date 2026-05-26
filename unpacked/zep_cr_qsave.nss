// OnClose for ZEP_CR_QUARANTINE chest.
// Saves the full current chest inventory to the campaign DB so it survives reboots.
// Overwrites the previous snapshot. Manually added items are included automatically.
void main() {
    object oChest = OBJECT_SELF;

    // Clear old snapshot keys
    int nOld = GetCampaignInt("craftdb", "chest_count");
    int i;
    for (i = 0; i < nOld; i++)
        DeleteCampaignVariable("craftdb", "chest_"+IntToString(i));

    // Save current inventory
    object oItem = GetFirstItemInInventory(oChest);
    int nCount = 0;
    while (GetIsObjectValid(oItem)) {
        StoreCampaignObject("craftdb", "chest_"+IntToString(nCount), oItem);
        nCount++;
        oItem = GetNextItemInInventory(oChest);
    }
    SetCampaignInt("craftdb", "chest_count", nCount);
}
