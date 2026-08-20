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
//
// Duplicate boxes: the pre-fix open scripts retrieved unconditionally, so a
// player who broke off the vault dialog and re-opened it ended up carrying
// several boxes with the same tag, each loaded from the same (unchanged) DB
// snapshot - a working item dupe (roadmap banking-duplicate-exploit). The open
// scripts are now per-index idempotent, and the commit helpers below drain every
// copy of a tag rather than just the first: the copy holding the most items is
// stored, the rest are destroyed, and the audit row's source is suffixed
// "+dupes" so the cleanup is visible.

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
        "source TEXT)");         // "dialog" | "area_exit" | "client_leave" | "open_*"
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

// Record a vault *open*. nBoxNum is the size of the account, nOpened the number
// of boxes actually handed over this time (0 when the player was already
// carrying them all). Repeated opens by the same CD key are the signature the
// duplication exploit left behind, so they are worth a row.
void Bank_LogOpen(object oPC, string sBoxType, int nBoxNum, int nOpened, string sSource)
{
    Bank_InitAudit();
    Bank_LogCommit(GetPCPublicCDKey(oPC), GetName(oPC), sBoxType, nBoxNum, nOpened, sSource);
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
// Commit one box tag
//
// Stores the copy of sBoxTag holding the most items into sDbKey (owner oOwner,
// OBJECT_INVALID for the global family keys), destroys every copy, and writes
// one bankaudit row. Returns the number of duplicate copies destroyed.
//
// The inventory is walked once to collect the copies as object-id strings before
// anything is counted or destroyed, so no inventory iterator is ever nested and
// DestroyObject's end-of-script deferral cannot confuse the scan.

int Bank_CommitBoxTag(object oPC, string sBoxTag, string sDbKey, object oOwner,
                      string sBoxType, int nBoxNum, string sSource)
{
    string sList = "";
    int nCopies = 0;

    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == sBoxTag)
        {
            sList = sList + ObjectToString(oItem) + ",";
            nCopies++;
        }
        oItem = GetNextItemInInventory(oPC);
    }

    if (nCopies == 0)
        return 0;

    // Pick the fullest copy as the survivor - committing an arbitrary one could
    // store an emptied box and destroy the full one.
    object oBest    = OBJECT_INVALID;
    int    nBestQty = -1;
    string sScan    = sList;
    while (GetStringLength(sScan) > 0)
    {
        int nSep = FindSubString(sScan, ",");
        if (nSep < 0)
            break;
        object oCopy = StringToObject(GetStringLeft(sScan, nSep));
        sScan = GetStringRight(sScan, GetStringLength(sScan) - nSep - 1);
        if (!GetIsObjectValid(oCopy))
            continue;
        int nQty = Bank_CountItems(oCopy);
        if (nQty > nBestQty)
        {
            nBestQty = nQty;
            oBest    = oCopy;
        }
    }

    if (!GetIsObjectValid(oBest))
        return 0;

    int nExtras = nCopies - 1;
    StoreCampaignObject(BANK_DB, sDbKey, oBest, oOwner);
    Bank_LogCommit(GetPCPublicCDKey(oPC), GetName(oPC), sBoxType, nBoxNum,
                   nBestQty, nExtras > 0 ? sSource + "+dupes" : sSource);

    // Destroy every copy, survivor included - it is now safely in the DB.
    sScan = sList;
    while (GetStringLength(sScan) > 0)
    {
        int nSep = FindSubString(sScan, ",");
        if (nSep < 0)
            break;
        object oCopy = StringToObject(GetStringLeft(sScan, nSep));
        sScan = GetStringRight(sScan, GetStringLength(sScan) - nSep - 1);
        if (GetIsObjectValid(oCopy))
            DestroyObject(oCopy);
    }

    if (nExtras > 0)
        WriteTimestampedLogEntry("BANK: destroyed " + IntToString(nExtras) +
            " duplicate " + sBoxType + " box(es) '" + sBoxTag + "' for " +
            GetName(oPC) + " [" + GetPCPublicCDKey(oPC) + "] on " + sSource);

    return nExtras;
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
    int iCounter;
    for (iCounter = 1; iCounter <= 5; iCounter++)
    {
        Bank_CommitBoxTag(oPC,
            "az_familybox_" + sCDKey + "_" + IntToString(iCounter),
            "fam_box_" + sCDKey + "_" + IntToString(iCounter),
            OBJECT_INVALID, "family", iCounter, sSource);
    }
}

void CommitStrongBoxes(object oPC, string sSource)
{
    Bank_InitAudit();
    string sCDKey = GetPCPublicCDKey(oPC);
    int iCounter;
    for (iCounter = 1; iCounter <= 5; iCounter++)
    {
        Bank_CommitBoxTag(oPC,
            "az_strongbox_" + sCDKey + "_" + IntToString(iCounter),
            "bank_box_" + IntToString(iCounter),
            oPC, "strong", iCounter, sSource);
    }
}
