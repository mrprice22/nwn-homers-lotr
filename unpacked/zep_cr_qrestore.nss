// OnOpen for ZEP_CR_QUARANTINE chest.
// After a reboot the chest is empty — restore from the last-close snapshot.
// Also pulls in any items quarantined since the last open.
// Items are cleared of crafting flags (Plot/Cursed/Stolen/TEMPITEM) so they
// can be picked up and given back to players.
void main() {
    object oChest  = OBJECT_SELF;
    object oOpener = GetLastOpenedBy();

    // --- Restore reboot snapshot if chest is currently empty ---
    if (!GetIsObjectValid(GetFirstItemInInventory(oChest))) {
        int nSnap = GetCampaignInt("craftdb", "chest_count");
        int i;
        for (i = 0; i < nSnap; i++) {
            object oItem = RetrieveCampaignObject("craftdb", "chest_"+IntToString(i), GetLocation(oChest), oChest);
            if (GetIsObjectValid(oItem)) {
                SetPlotFlag(oItem, FALSE);
                SetItemCursedFlag(oItem, FALSE);
                SetStolenFlag(oItem, FALSE);
                DeleteLocalInt(oItem, "ZEP_CR_TEMPITEM");
            }
            DeleteCampaignVariable("craftdb", "chest_"+IntToString(i));
        }
        SetCampaignInt("craftdb", "chest_count", 0);
        if (nSnap > 0)
            SendMessageToPC(oOpener, "[Quarantine] Restored " + IntToString(nSnap) + " item(s) from reboot snapshot.");
    }

    // --- Pull in newly quarantined items ---
    int nQuar = GetCampaignInt("craftdb", "quarantine_count");
    if (nQuar == 0) {
        SendMessageToPC(oOpener, "[Quarantine] No new quarantined items.");
        return;
    }
    int n, nRestored = 0;
    for (n = 0; n < nQuar; n++) {
        string sKey  = "quarantine_" + IntToString(n);
        string sInfo = GetCampaignString("craftdb", sKey + "_info");
        object oItem = RetrieveCampaignObject("craftdb", sKey, GetLocation(oChest), oChest);
        if (GetIsObjectValid(oItem)) {
            SetPlotFlag(oItem, FALSE);
            SetItemCursedFlag(oItem, FALSE);
            SetStolenFlag(oItem, FALSE);
            DeleteLocalInt(oItem, "ZEP_CR_TEMPITEM");
            nRestored++;
            if (sInfo != "")
                SendMessageToPC(oOpener, "[Quarantine] " + sInfo);
        }
        DeleteCampaignVariable("craftdb", sKey);
        DeleteCampaignVariable("craftdb", sKey + "_info");
    }
    SetCampaignInt("craftdb", "quarantine_count", 0);
    SendMessageToPC(oOpener, "[Quarantine] Added " + IntToString(nRestored) + "/" + IntToString(nQuar) + " newly quarantined item(s).");
}
