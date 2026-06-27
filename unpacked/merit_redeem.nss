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
//   5037        Player: confirmation-step prompt (delivery type / affordability)
//   5038        DM: selected-request description (detail entry)
//   5040-5048   DM: pending-redemption list slot labels
//   5049        DM: pending-redemption list header
//   5050-5058   Player: own-pending list slot labels ([Cancel] rows)
//   5059        Player: own-pending list header
//   5060-5068   Player: category option slot labels (with red placeholder prefix)
//   5070-5078   Player: tournament-gear picker slot labels (item names)
// Shared per-speaker locals "merit_lslot_0".."merit_lslot_8" hold the row/reward
// id for the currently displayed list (0 = empty). DM list also stashes
// "merit_lslot_<i>_desc" for the detail entry. The confirmation step uses
// separate locals: merit_pick_id / merit_pick_dm / merit_pick_afford, and the
// tournament picker uses merit_tslot_<i> (resref) + merit_tpage_off/total — all
// distinct from merit_lslot_* so "Nevermind" returns to the option list intact.

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
        case 203: r.cost = 4;  r.needs_dm = 0; r.label = "1 week of premium for the whole server (+ your name in login welcome)"; break;
        case 204: r.cost = 8;  r.needs_dm = 0; r.label = "1 month of premium for the whole server (+ your name in login welcome)"; break;

        // --- Vanity & swag ---
        case 301: r.cost = 5;   r.needs_dm = 1; r.label = "Graffiti the Well of Eru with your name & description"; break;
        case 302: r.cost = 10;  r.needs_dm = 0; r.label = "Tournament gear - pick one piece"; break;
        case 303: r.cost = 25;  r.needs_dm = 1; r.label = "A hand-made duct-tape wallet mailed to you (3 colours + design)"; break;
        case 304: r.cost = 100; r.needs_dm = 1; r.label = "Become a DM"; break;

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
        case MERIT_CAT_VANITY:    return 4;
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
        case MERIT_CAT_VANITY:    return 301 + nIdx;  // 301..304
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

    Merit_Ledger(sCdKey, GetPCPlayerName(oPC), -r.cost,
        "request #" + IntToString(nReqId) + ": " + r.label, nReqId);

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
    Merit_Ledger(sOwner, sPName, nCost,
        "cancel #" + IntToString(nReqId) + " refund: " + sLabel, nReqId);

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
        // Only the nominal instant rewards (teleports/premium) are still
        // unwired placeholders. DM-fulfilled options work today (a DM delivers
        // them) and tournament gear (302) delivers on the spot, so neither
        // carries the red [PLACEHOLDER] prefix.
        string sPrefix = (r.needs_dm == 1 || nId == 302) ? "" : MERIT_PH;
        SetCustomToken(5060 + i, sPrefix + r.label + " [" + IntToString(r.cost) + " merit]");
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

// ------------------------------------------------------------
// Tournament gear (reward 302) — curated picker. One solid item per weapon
// type plus armour, tower shield, gauntlets, and bows (dupes/mislabeled
// blueprints dropped). The chosen piece is delivered instantly.

int Merit_TournCount() { return 23; }

string Merit_TournResref(int i)
{
    switch (i)
    {
        case 0:  return "tournamaentlongs";  // Longsword (sic: blueprint resref)
        case 1:  return "tournamentshorts";  // Short Sword
        case 2:  return "tournamentgreats";  // Greatsword
        case 3:  return "item093";           // Bastard Sword
        case 4:  return "tournamentscimit";  // Scimitar
        case 5:  return "tournamentdagger";  // Dagger
        case 6:  return "tournamentkama";    // Kama
        case 7:  return "tournamentkuk001";  // Kukri
        case 8:  return "tournamentclub";    // Club
        case 9:  return "tournamentmace";    // Mace
        case 10: return "tournamentmornin";  // Morningstar
        case 11: return "tournamentwarham";  // Warhammer
        case 12: return "tournamentbattle";  // Battleaxe
        case 13: return "tournamentgreata";  // Greataxe
        case 14: return "tournamenthalber";  // Halberd
        case 15: return "tournamentscythe";  // Scythe
        case 16: return "tournamentmaugdo";  // Maug Double Sword
        case 17: return "tournamentlongbo";  // Longbow
        case 18: return "tournamentshortb";  // Shortbow
        case 19: return "tournamentdarts";   // Darts
        case 20: return "tournamentarmour";  // Armour
        case 21: return "tournamenttowers";  // Tower Shield
        case 22: return "tournamentgauntl";  // Gauntlets
    }
    return "";
}

string Merit_TournName(int i)
{
    switch (i)
    {
        case 0:  return "Tournament Longsword";
        case 1:  return "Tournament Short Sword";
        case 2:  return "Tournament Greatsword";
        case 3:  return "Tournament Bastard Sword";
        case 4:  return "Tournament Scimitar";
        case 5:  return "Tournament Dagger";
        case 6:  return "Tournament Kama";
        case 7:  return "Tournament Kukri";
        case 8:  return "Tournament Club";
        case 9:  return "Tournament Mace";
        case 10: return "Tournament Morningstar";
        case 11: return "Tournament Warhammer";
        case 12: return "Tournament Battleaxe";
        case 13: return "Tournament Greataxe";
        case 14: return "Tournament Halberd";
        case 15: return "Tournament Scythe";
        case 16: return "Tournament Maug Double Sword";
        case 17: return "Tournament Longbow";
        case 18: return "Tournament Shortbow";
        case 19: return "Tournament Darts";
        case 20: return "Tournament Armour";
        case 21: return "Tournament Tower Shield";
        case 22: return "Tournament Gauntlets";
    }
    return "";
}

// Build the tournament picker page -> tokens 5070-5078, locals merit_tslot_<i>.
void Merit_BuildTournament(object oPC)
{
    int nOff   = GetLocalInt(oPC, "merit_tpage_off");
    int nTotal = Merit_TournCount();
    SetLocalInt(oPC, "merit_tpage_total", nTotal);

    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalString(oPC, "merit_tslot_" + IntToString(i));
        DeleteLocalString(oPC, "merit_tslot_" + IntToString(i) + "_name");
        SetCustomToken(5070 + i, "");
    }
    for (i = 0; i < 9; i++)
    {
        int idx = nOff + i;
        if (idx >= nTotal) break;
        SetLocalString(oPC, "merit_tslot_" + IntToString(i), Merit_TournResref(idx));
        SetLocalString(oPC, "merit_tslot_" + IntToString(i) + "_name", Merit_TournName(idx));
        SetCustomToken(5070 + i, Merit_TournName(idx));
    }
}

// ------------------------------------------------------------
// Confirmation step (token 5037 + merit_pick_* locals on the speaker)

void Merit_PrepConfirm(object oPC, int nId)
{
    struct merit_reward r = Merit_GetReward(nId);
    string sCdKey = GetPCPublicCDKey(oPC);
    int nAvail = Merit_Available(sCdKey);
    int bAfford = (nAvail >= r.cost);

    SetLocalInt(oPC, "merit_pick_id", nId);
    SetLocalInt(oPC, "merit_pick_dm", r.needs_dm);
    SetLocalInt(oPC, "merit_pick_afford", bAfford);

    if (!r.valid)
    {
        SetCustomToken(5037, "Hmm, I can't find that reward. Try again?");
        SetLocalInt(oPC, "merit_pick_afford", FALSE);
        return;
    }
    if (!bAfford)
    {
        SetCustomToken(5037, "I'm afraid '" + r.label + "' costs " + IntToString(r.cost)
            + " merit, and you've only " + IntToString(nAvail)
            + " available. Best earn a bit more first.");
        return;
    }
    if (nId == 302)
    {
        SetLocalInt(oPC, "merit_tpage_off", 0);
        Merit_BuildTournament(oPC);
        SetCustomToken(5037, "A fine choice - " + IntToString(r.cost)
            + " merit for one piece of Tournament gear, yours on the spot (this cannot be undone). Pick one:");
        return;
    }
    if (r.needs_dm == 0)
        SetCustomToken(5037, "Reward of '" + r.label + "' to be granted instantly -- this cannot be undone. ("
            + IntToString(r.cost) + " merit)");
    else
        SetCustomToken(5037, "Reward of '" + r.label
            + "' to be fulfilled by a DM later, as time and bandwidth allow. ("
            + IntToString(r.cost) + " merit)");
}

// ------------------------------------------------------------
// Instant grant (needs_dm == 0): spend, record a fulfilled row, ledger, deliver.

int Merit_GrantInstant(object oPC, int nId)
{
    struct merit_reward r = Merit_GetReward(nId);
    if (!r.valid) return FALSE;

    string sCdKey = GetPCPublicCDKey(oPC);
    if (Merit_Available(sCdKey) < r.cost)
    {
        SendMessageToPC(oPC, "[Merit] You can no longer afford that.");
        return FALSE;
    }

    Merit_Spend(sCdKey, r.cost);

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "INSERT INTO redemptions(cdkey, player_name, reward_id, reward_label, cost, needs_dm, status, resolved_by, resolved_at)"
        + " VALUES(@k, @n, @r, @l, @c, 0, 'fulfilled', 'auto', datetime('now'))");
    SqlBindString(q, "@k", sCdKey);
    SqlBindString(q, "@n", GetPCPlayerName(oPC));
    SqlBindInt(q, "@r", nId);
    SqlBindString(q, "@l", r.label);
    SqlBindInt(q, "@c", r.cost);
    SqlStep(q);

    int nReqId = 0;
    sqlquery qid = SqlPrepareQueryCampaign(MERIT_DB, "SELECT last_insert_rowid()");
    if (SqlStep(qid)) nReqId = SqlGetInt(qid, 0);

    Merit_Ledger(sCdKey, GetPCPlayerName(oPC), -r.cost,
        "instant #" + IntToString(nReqId) + ": " + r.label, nReqId);
    Merit_SetNpcTokens(oPC);

    SendMessageToPC(oPC, "[Merit] Redeemed instantly: " + r.label + " ("
        + IntToString(r.cost) + " merit). Logged as #" + IntToString(nReqId) + ".");
    SendMessageToAllDMs("[Merit] " + GetPCPlayerName(oPC) + " redeemed (instant) #"
        + IntToString(nReqId) + ": " + r.label + " (" + IntToString(r.cost) + " merit).");
    return TRUE;
}

// Tournament instant grant — like Merit_GrantInstant but delivers a chosen item.
int Merit_GrantTournament(object oPC, string sResref, string sItemName)
{
    struct merit_reward r = Merit_GetReward(302);

    string sCdKey = GetPCPublicCDKey(oPC);
    if (Merit_Available(sCdKey) < r.cost)
    {
        SendMessageToPC(oPC, "[Merit] You can no longer afford that.");
        return FALSE;
    }

    // Deliver the item FIRST and confirm it exists before spending any merit.
    // CreateItemOnObject only returns an invalid object when the item truly
    // could not be made (bad blueprint); when the PC's inventory is full the
    // item is still created but lands on the ground at their feet. Both count as
    // "delivered" for billing purposes -- the player has the item either way --
    // so we only abort (no charge) when nothing was created at all.
    object oItem = CreateItemOnObject(sResref, oPC);
    if (!GetIsObjectValid(oItem))
    {
        SendMessageToPC(oPC, "[Merit] Could not create " + sItemName + " (item '"
            + sResref + "') - no merit was spent. Please try again, or tell a DM "
            + "if it keeps failing.");
        return FALSE;
    }
    int bOnGround = (GetItemPossessor(oItem) != oPC);  // inventory was full

    // Delivery confirmed (in inventory or on the ground); now charge and record.
    Merit_Spend(sCdKey, r.cost);
    string sLabel = "Tournament gear: " + sItemName;

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "INSERT INTO redemptions(cdkey, player_name, reward_id, reward_label, cost, needs_dm, status, resolved_by, resolved_at)"
        + " VALUES(@k, @n, 302, @l, @c, 0, 'fulfilled', 'auto', datetime('now'))");
    SqlBindString(q, "@k", sCdKey);
    SqlBindString(q, "@n", GetPCPlayerName(oPC));
    SqlBindString(q, "@l", sLabel);
    SqlBindInt(q, "@c", r.cost);
    SqlStep(q);

    int nReqId = 0;
    sqlquery qid = SqlPrepareQueryCampaign(MERIT_DB, "SELECT last_insert_rowid()");
    if (SqlStep(qid)) nReqId = SqlGetInt(qid, 0);

    Merit_Ledger(sCdKey, GetPCPlayerName(oPC), -r.cost,
        "instant #" + IntToString(nReqId) + ": " + sLabel, nReqId);
    Merit_SetNpcTokens(oPC);

    if (bOnGround)
        SendMessageToPC(oPC, "[Merit] Granted " + sItemName + " (" + IntToString(r.cost)
            + " merit), but your inventory was full so it dropped at your feet - "
            + "pick it up off the ground!");
    else
        SendMessageToPC(oPC, "[Merit] Granted " + sItemName + " ("
            + IntToString(r.cost) + " merit). Check your inventory!");
    SendMessageToAllDMs("[Merit] " + GetPCPlayerName(oPC) + " redeemed Tournament gear #"
        + IntToString(nReqId) + ": " + sItemName + ".");
    return TRUE;
}
