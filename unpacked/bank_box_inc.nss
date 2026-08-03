// bank_box_inc.nss - Bank of Bree storage commit helpers + audit log
//
// Both Bank of Bree storage types spawn a live placeable container into the
// player's inventory while the vault dialog is open, and only serialize it back
// to the "bankdb" campaign DB (StoreCampaignObject) when the player finishes the
// conversation. If the player leaves the bank area or logs out before that
// commit fires, anything added that session is lost.
//
// These helpers centralise the commit loops so every exit path (the close
// dialog, the area OnExit, and the module OnClientLeave) re-stores boxes the
// same way:
//   CommitFamilyBoxes  -> az_familybox_<CDKey>_N  -> "fam_box_<CDKey>_N" (global key)
//   CommitStrongBoxes  -> az_strongbox_<CDKey>_N  -> "bank_box_N"        (owner = oPC)
//
// Each successful store is recorded in the bankaudit table (same bankdb file) so
// future loss reports can be investigated - the previous DB had no timestamps or
// transaction log, so past losses could not be confirmed.

const string BANK_DB = "bankdb";

// ------------------------------------------------------------
// Audit log

void Bank_InitAudit()
{
    sqlquery q = SqlPrepareQueryCampaign(BANK_DB,
        "CREATE TABLE IF NOT EXISTS bankaudit (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "ts TEXT NOT NULL DEFAULT (datetime('now'))," +
        "cdkey TEXT," +
        "char_name TEXT," +
        "box_type TEXT," +       // "family" | "strong"
        "box_num INTEGER," +
        "item_count INTEGER," +
        "source TEXT)");         // "dialog" | "area_exit" | "client_leave"
    SqlStep(q);
}

void Bank_LogCommit(string sCDKey, string sCharName, string sBoxType,
                    int nBoxNum, int nItems, string sSource)
{
    sqlquery q = SqlPrepareQueryCampaign(BANK_DB,
        "INSERT INTO bankaudit(cdkey,char_name,box_type,box_num,item_count,source)" +
        " VALUES(@k,@n,@t,@b,@i,@s)");
    SqlBindString(q, "@k", sCDKey);
    SqlBindString(q, "@n", sCharName);
    SqlBindString(q, "@t", sBoxType);
    SqlBindInt   (q, "@b", nBoxNum);
    SqlBindInt   (q, "@i", nItems);
    SqlBindString(q, "@s", sSource);
    SqlStep(q);
}

// Count of items currently inside a container object.
int Bank_CountItems(object oBox)
{
    int nCount = 0;
    object oItem = GetFirstItemInInventory(oBox);
    while (GetIsObjectValid(oItem))
    {
        nCount++;
        oItem = GetNextItemInInventory(oBox);
    }
    return nCount;
}

// ------------------------------------------------------------
// Commit loops
//
// sSource identifies the calling path for the audit log ("dialog", "area_exit",
// "client_leave"). Both helpers are safe to call when the player has no boxes in
// inventory - they simply do nothing.

void CommitFamilyBoxes(object oPC, string sSource)
{
    Bank_InitAudit();
    string sCDKey = GetPCPublicCDKey(oPC);
    string sName  = GetName(oPC);
    int iCounter;
    for (iCounter = 1; iCounter <= 5; iCounter++)
    {
        string sBoxTag = "az_familybox_" + sCDKey + "_" + IntToString(iCounter);
        object oBox = GetItemPossessedBy(oPC, sBoxTag);
        if (GetIsObjectValid(oBox))
        {
            int nItems = Bank_CountItems(oBox);
            StoreCampaignObject(BANK_DB, "fam_box_" + sCDKey + "_" + IntToString(iCounter), oBox);
            Bank_LogCommit(sCDKey, sName, "family", iCounter, nItems, sSource);
            DestroyObject(oBox);
        }
    }
}

void CommitStrongBoxes(object oPC, string sSource)
{
    Bank_InitAudit();
    string sCDKey = GetPCPublicCDKey(oPC);
    string sName  = GetName(oPC);
    int iCounter;
    for (iCounter = 1; iCounter <= 5; iCounter++)
    {
        string sBoxTag = "az_strongbox_" + sCDKey + "_" + IntToString(iCounter);
        object oBox = GetItemPossessedBy(oPC, sBoxTag);
        if (GetIsObjectValid(oBox))
        {
            int nItems = Bank_CountItems(oBox);
            StoreCampaignObject(BANK_DB, "bank_box_" + IntToString(iCounter), oBox, oPC);
            Bank_LogCommit(sCDKey, sName, "strong", iCounter, nItems, sSource);
            DestroyObject(oBox);
        }
    }
}
