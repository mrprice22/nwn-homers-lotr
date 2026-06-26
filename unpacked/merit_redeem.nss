// merit_redeem.nss — Merit redemption catalogue + request/approval engine.
//
// Earned merit is never decremented (it stays bugs*1 + exploits*3 + features*2,
// in merit_db.nss). Spending is tracked entirely through players.merit_spent via
// an ESCROW model:
//   * Merit_RequestById debits the cost immediately and inserts a 'pending'
//     redemptions row. The server-side affordability check there guarantees
//     merit_spent can never exceed earned.
//   * Cancelling a pending request refunds the escrow (Merit_Refund).
//   * Fulfilling keeps the debit.
//
// This pass ships every documented option as a PLACEHOLDER (red prefix). Nothing
// is auto-granted; each selection creates a request a DM fulfils or cancels.
// See CLAUDE-merit.md for how to add an option or graduate one to automated.
//
// Custom token map (this file):
//   5038        DM: selected-request description (detail entry)
//   5040-5048   DM: pending-redemption list slot labels
//   5049        DM: pending-redemption list header
//   5050-5058   Player: own-pending list slot labels ([Cancel] rows)
//   5059        Player: own-pending list header
//   5060-5068   Player: category option slot labels (with red placeholder prefix)
// Shared per-speaker locals "merit_lslot_0".."merit_lslot_8" hold the row/reward
// id for the currently displayed list (0 = empty). DM list also stashes
// "merit_lslot_<i>_desc" for the detail entry.

#include "merit_db"

// Red "[PLACEHOLDER] " prefix. MERITREDOPEN is replaced post-write with the raw
// colour bytes "<c" + FF 01 01 + ">" (null-free bright red, repo convention).
const string MERIT_PH = "<c�>[PLACEHOLDER]</c> ";

// Categories (match the conversation sub-menus and Merit_CatReward below).
const int MERIT_CAT_TELE      = 0;
const int MERIT_CAT_PREM      = 1;
const int MERIT_CAT_VANITY    = 2;
const int MERIT_CAT_HOUSESIZE = 3;
const int MERIT_CAT_HOUSEFEAT = 4;

struct merit_reward
{
    int    valid;
    int    cost;
    int    needs_dm;
    string label;
};

// ------------------------------------------------------------
// Catalogue — single source of truth. To add a redemption: add a case here and
// register its id in Merit_CatReward / Merit_CatCount.

struct merit_reward Merit_GetReward(int nId)
{
    struct merit_reward r;
    r.valid = 1;
    switch (nId)
    {
        // --- Teleport & travel (rest-menu features) ---
        case 101: r.cost = 3;  r.needs_dm = 0; r.label = "Teleport to your party leader"; break;
        case 102: r.cost = 4;  r.needs_dm = 0; r.label = "Teleport to your last Well-of-Eru save point"; break;
        case 103: r.cost = 6;  r.needs_dm = 0; r.label = "Save-slot teleport (Slot 1)"; break;
        case 104: r.cost = 7;  r.needs_dm = 0; r.label = "Save-slot teleport (Slot 2)"; break;
        case 105: r.cost = 8;  r.needs_dm = 0; r.label = "Save-slot teleport (Slot 3)"; break;
        case 106: r.cost = 9;  r.needs_dm = 0; r.label = "Save-slot teleport (Slot 4)"; break;
        case 107: r.cost = 10; r.needs_dm = 0; r.label = "Save-slot teleport (Slot 5)"; break;

        // --- Premium boosts (3x gold & XP) ---
        case 201: r.cost = 1;  r.needs_dm = 0; r.label = "1 week of premium for you (3x gold & XP)"; break;
        case 202: r.cost = 3;  r.needs_dm = 0; r.label = "1 month of premium for you"; break;
        case 203: r.cost = 4;  r.needs_dm = 1; r.label = "1 week of premium for the whole server (+ your name in login welcome)"; break;
        case 204: r.cost = 8;  r.needs_dm = 1; r.label = "1 month of premium for the whole server (+ your name in login welcome)"; break;

        // --- Vanity & swag ---
        case 301: r.cost = 5;  r.needs_dm = 1; r.label = "Graffiti the Well of Eru with your name & description"; break;
        case 302: r.cost = 10; r.needs_dm = 1; r.label = "A set of Tournament equipment"; break;
        case 303: r.cost = 25; r.needs_dm = 1; r.label = "A hand-made duct-tape wallet mailed to you (3 colours + design)"; break;

        // --- Player housing: area size (cost scales with Length x Width) ---
        case 401: r.cost = 1;  r.needs_dm = 1; r.label = "Player home - area size 2 (LxW)"; break;
        case 402: r.cost = 2;  r.needs_dm = 1; r.label = "Player home - area size 4 (LxW)"; break;
        case 403: r.cost = 3;  r.needs_dm = 1; r.label = "Player home - area size 8 (LxW)"; break;
        case 404: r.cost = 4;  r.needs_dm = 1; r.label = "Player home - area size 16 (LxW)"; break;
        case 405: r.cost = 5;  r.needs_dm = 1; r.label = "Player home - area size 32 (LxW)"; break;
        case 406: r.cost = 6;  r.needs_dm = 1; r.label = "Player home - area size 64 (LxW)"; break;
        case 407: r.cost = 7;  r.needs_dm = 1; r.label = "Player home - area size 81 (LxW)"; break;
        case 408: r.cost = 8;  r.needs_dm = 1; r.label = "Player home - area size 100 (LxW)"; break;

        // --- Player housing: optional add-ons ---
        case 501: r.cost = 2;  r.needs_dm = 1; r.label = "Home add-on: persistent storage chest (shared across your characters)"; break;
        case 502: r.cost = 2;  r.needs_dm = 1; r.label = "Home add-on: a Well-of-Eru store (100K buy limit; you pick NPC name & look)"; break;
        case 503: r.cost = 5;  r.needs_dm = 1; r.label = "Home add-on: a Tagget-tier forge"; break;
        case 504: r.cost = 10; r.needs_dm = 1; r.label = "Home add-on: a Rivendell-tier forge"; break;
        case 505: r.cost = 15; r.needs_dm = 1; r.label = "Home add-on: a Balrog-tier forge"; break;

        default:  r.valid = 0; r.cost = 0; r.needs_dm = 1; r.label = ""; break;
    }
    return r;
}

int Merit_CatCount(int nCat)
{
    switch (nCat)
    {
        case MERIT_CAT_TELE:      return 7;
        case MERIT_CAT_PREM:      return 4;
        case MERIT_CAT_VANITY:    return 3;
        case MERIT_CAT_HOUSESIZE: return 8;
        case MERIT_CAT_HOUSEFEAT: return 5;
    }
    return 0;
}

int Merit_CatReward(int nCat, int nIdx)
{
    switch (nCat)
    {
        case MERIT_CAT_TELE:      return 101 + nIdx;  // 101..107
        case MERIT_CAT_PREM:      return 201 + nIdx;  // 201..204
        case MERIT_CAT_VANITY:    return 301 + nIdx;  // 301..303
        case MERIT_CAT_HOUSESIZE: return 401 + nIdx;  // 401..408
        case MERIT_CAT_HOUSEFEAT: return 501 + nIdx;  // 501..505
    }
    return 0;
}

// ------------------------------------------------------------
// Helpers

// Message the holder of sCdKey if they are currently online.
void Merit_NotifyOnline(string sCdKey, string sMsg)
{
    object o = GetFirstPC();
    while (GetIsObjectValid(o))
    {
        if (GetPCPublicCDKey(o) == sCdKey)
        {
            SendMessageToPC(o, sMsg);
            return;
        }
        o = GetNextPC();
    }
}

// ------------------------------------------------------------
// Request / cancel / fulfill

// Returns TRUE if a pending request was created (cost escrowed).
int Merit_RequestById(object oPC, int nId)
{
    struct merit_reward r = Merit_GetReward(nId);
    if (!r.valid)
    {
        SendMessageToPC(oPC, "[Merit] Unknown reward.");
        return FALSE;
    }

    string sCdKey = GetPCPublicCDKey(oPC);
    int nAvail = Merit_Available(sCdKey);
    if (nAvail < r.cost)
    {
        SendMessageToPC(oPC, "[Merit] That costs " + IntToString(r.cost)
            + " merit, but you only have " + IntToString(nAvail) + " available.");
        return FALSE;
    }

    Merit_Spend(sCdKey, r.cost);   // escrow the cost

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "INSERT INTO redemptions(cdkey, player_name, reward_id, reward_label, cost, needs_dm)"
        + " VALUES(@k, @n, @r, @l, @c, @d)");
    SqlBindString(q, "@k", sCdKey);
    SqlBindString(q, "@n", GetPCPlayerName(oPC));
    SqlBindInt(q, "@r", nId);
    SqlBindString(q, "@l", r.label);
    SqlBindInt(q, "@c", r.cost);
    SqlBindInt(q, "@d", r.needs_dm);
    SqlStep(q);

    int nReqId = 0;
    sqlquery qid = SqlPrepareQueryCampaign(MERIT_DB, "SELECT last_insert_rowid()");
    if (SqlStep(qid)) nReqId = SqlGetInt(qid, 0);

    Merit_SetNpcTokens(oPC);  // refresh the displayed balance

    SendMessageToPC(oPC, "[Merit] Request #" + IntToString(nReqId) + " submitted: "
        + r.label + ". " + IntToString(r.cost)
        + " merit is now held. A DM will fulfil it; cancel any time from "
        + "'My pending requests' for a full refund.");

    SendMessageToAllDMs("[Merit] " + GetPCPlayerName(oPC) + " requested redemption #"
        + IntToString(nReqId) + ": " + r.label + " (" + IntToString(r.cost) + " merit"
        + (r.needs_dm ? ", DM approval" : "") + "). EmoteWand > [Admin] Merit Redemptions.");
    return TRUE;
}

// bIsDm: a player may only cancel their own pending request; a DM may cancel any.
int Merit_CancelRedemption(int nReqId, string sActorCdKey, string sActorName, int bIsDm)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT cdkey, player_name, reward_label, cost, status FROM redemptions WHERE id=@i");
    SqlBindInt(q, "@i", nReqId);
    if (!SqlStep(q)) return FALSE;

    string sOwner  = SqlGetString(q, 0);
    string sPName  = SqlGetString(q, 1);
    string sLabel  = SqlGetString(q, 2);
    int    nCost   = SqlGetInt(q, 3);
    string sStatus = SqlGetString(q, 4);

    if (sStatus != "pending") return FALSE;
    if (!bIsDm && sOwner != sActorCdKey) return FALSE;

    Merit_Refund(sOwner, nCost);

    sqlquery qu = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE redemptions SET status='cancelled', resolved_by=@by, resolved_at=datetime('now')"
        + " WHERE id=@i");
    SqlBindString(qu, "@by", (bIsDm ? "DM:" : "") + sActorName);
    SqlBindInt(qu, "@i", nReqId);
    SqlStep(qu);

    Merit_NotifyOnline(sOwner, "[Merit] Redemption #" + IntToString(nReqId) + " ("
        + sLabel + ") was cancelled. " + IntToString(nCost) + " merit refunded.");
    SendMessageToAllDMs("[Merit] Redemption #" + IntToString(nReqId) + " (" + sLabel
        + ") cancelled by " + sActorName + "; " + IntToString(nCost) + " merit refunded to "
        + sPName + ".");
    return TRUE;
}

int Merit_FulfillRedemption(int nReqId, string sDmName)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT cdkey, player_name, reward_label, cost, status FROM redemptions WHERE id=@i");
    SqlBindInt(q, "@i", nReqId);
    if (!SqlStep(q)) return FALSE;

    string sOwner  = SqlGetString(q, 0);
    string sPName  = SqlGetString(q, 1);
    string sLabel  = SqlGetString(q, 2);
    string sStatus = SqlGetString(q, 4);

    if (sStatus != "pending") return FALSE;

    sqlquery qu = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE redemptions SET status='fulfilled', resolved_by=@by, resolved_at=datetime('now')"
        + " WHERE id=@i");
    SqlBindString(qu, "@by", "DM:" + sDmName);
    SqlBindInt(qu, "@i", nReqId);
    SqlStep(qu);

    Merit_NotifyOnline(sOwner, "[Merit] Your redemption #" + IntToString(nReqId) + " ("
        + sLabel + ") has been fulfilled by a DM. Enjoy!");
    SendMessageToAllDMs("[Merit] Redemption #" + IntToString(nReqId) + " (" + sLabel
        + ") for " + sPName + " marked fulfilled by " + sDmName + ".");
    return TRUE;
}

// ------------------------------------------------------------
// List builders (set tokens + per-speaker slot locals before the entry renders)

// Player: options in a category -> tokens 5060-5068, locals merit_lslot_<i>.
void Merit_BuildCategory(object oPC, int nCat)
{
    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalInt(oPC, "merit_lslot_" + IntToString(i));
        SetCustomToken(5060 + i, "");
    }

    int nCount = Merit_CatCount(nCat);
    for (i = 0; i < nCount && i < 9; i++)
    {
        int nId = Merit_CatReward(nCat, i);
        struct merit_reward r = Merit_GetReward(nId);
        SetLocalInt(oPC, "merit_lslot_" + IntToString(i), nId);
        SetCustomToken(5060 + i, MERIT_PH + r.label + " [" + IntToString(r.cost) + " merit]");
    }
}

// Player: own pending requests -> tokens 5050-5058 (+5059 header), locals merit_lslot_<i>.
void Merit_BuildMyPending(object oPC)
{
    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalInt(oPC, "merit_lslot_" + IntToString(i));
        SetCustomToken(5050 + i, "");
    }

    string sCdKey = GetPCPublicCDKey(oPC);

    sqlquery qc = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT COUNT(*) FROM redemptions WHERE cdkey=@k AND status='pending'");
    SqlBindString(qc, "@k", sCdKey);
    int nCount = 0;
    if (SqlStep(qc)) nCount = SqlGetInt(qc, 0);
    SetCustomToken(5059, nCount
        ? ("You have " + IntToString(nCount) + " pending request(s)"
           + (nCount > 9 ? " (showing first 9)" : "") + ". Select one to cancel for a refund:")
        : "You have no pending requests.");

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT id, reward_label, cost FROM redemptions WHERE cdkey=@k AND status='pending'"
        + " ORDER BY requested_at LIMIT 9");
    SqlBindString(q, "@k", sCdKey);
    i = 0;
    while (SqlStep(q) && i < 9)
    {
        int nId    = SqlGetInt(q, 0);
        string sL  = SqlGetString(q, 1);
        int nCost  = SqlGetInt(q, 2);
        SetLocalInt(oPC, "merit_lslot_" + IntToString(i), nId);
        SetCustomToken(5050 + i, "[Cancel] #" + IntToString(nId) + " " + sL
            + " (" + IntToString(nCost) + " merit)");
        i++;
    }
}

// DM: all pending requests, paged -> tokens 5040-5048 (+5049 header),
// locals merit_lslot_<i> and merit_lslot_<i>_desc.
void Merit_BuildPendingPage(object oDM)
{
    int nOff = GetLocalInt(oDM, "merit_rpage_off");

    sqlquery qc = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT COUNT(*) FROM redemptions WHERE status='pending'");
    int nTotal = 0;
    if (SqlStep(qc)) nTotal = SqlGetInt(qc, 0);
    SetLocalInt(oDM, "merit_rpage_total", nTotal);

    int nPages = (nTotal + 8) / 9;
    if (nPages == 0) nPages = 1;
    int nPage = nOff / 9 + 1;
    SetCustomToken(5049, IntToString(nTotal) + " pending  (page "
        + IntToString(nPage) + " of " + IntToString(nPages) + ")");

    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalInt(oDM, "merit_lslot_" + IntToString(i));
        DeleteLocalString(oDM, "merit_lslot_" + IntToString(i) + "_desc");
        SetCustomToken(5040 + i, "(empty)");
    }

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT id, player_name, reward_label, cost, needs_dm FROM redemptions"
        + " WHERE status='pending' ORDER BY requested_at LIMIT 9 OFFSET @o");
    SqlBindInt(q, "@o", nOff);
    i = 0;
    while (SqlStep(q) && i < 9)
    {
        int nId    = SqlGetInt(q, 0);
        string sN  = SqlGetString(q, 1);
        string sL  = SqlGetString(q, 2);
        int nCost  = SqlGetInt(q, 3);
        int nDm    = SqlGetInt(q, 4);
        string sDesc = "#" + IntToString(nId) + " " + sN + ": " + sL
            + " (" + IntToString(nCost) + " merit" + (nDm ? ", DM approval" : "") + ")";
        SetLocalInt(oDM, "merit_lslot_" + IntToString(i), nId);
        SetLocalString(oDM, "merit_lslot_" + IntToString(i) + "_desc", sDesc);
        SetCustomToken(5040 + i, sDesc);
        i++;
    }
}
