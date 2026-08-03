void ForgeLog(string sMsg)
{
    if (!GetLocalInt(GetModule(), "FORGE_DEBUG")) return;
    string sLine = "[FORGE] " + sMsg;
    WriteTimestampedLogEntry(sLine);
    SendMessageToAllDMs(sLine);
}

void main()
{
    WriteTimestampedLogEntry("[FORGE] removeallitems: forge_item_mid opened on " + GetName(OBJECT_SELF));
    ForgeLog("removeallitems (forge Entry[0] fired): NPC=" + GetName(OBJECT_SELF) + " - forge_item_mid.dlg is open");
    object oItem = GetFirstItemInInventory(OBJECT_SELF);
    while (oItem != OBJECT_INVALID)
    {
        DestroyObject(oItem);
        oItem = GetNextItemInInventory(OBJECT_SELF);
    }
}
