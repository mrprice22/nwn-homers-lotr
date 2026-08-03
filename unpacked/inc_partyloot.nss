// inc_partyloot - WoW-style party loot roll (Need / Greed / Pass) via NUI.
//
// Triggered from the OnAcquireItem hook (acquireditem_tag.nss) when a PC picks
// up an item worth >= the party's minimum and other eligible party members are
// in the same area. Each participant gets a clickable NUI popup; highest Need
// wins (else highest Greed; Pass cannot win). The looter participates and keeps
// the item on a self-win, otherwise the item auto-transfers to the winner.
//
// Settings (persisted in the campaign DB, keyed by the PC):
//   "partyloot" / "optout"    per-PC opt-out flag        (set in rest menu)
//   "partyloot" / "disabled"  party-leader disable flag  (set in rest menu)
//   "partyloot" / "threshold" party-leader minimum gp    (set in rest menu)
// The leader is GetFactionLeader(oPC); a solo PC is their own leader.
//
// See [[project_forge_system]]-style transactional care: PL_Resolve is
// idempotent (guarded by "pl_resolved") so the 30s timeout and the
// all-responded early-resolve can never both fire the payout.

#include "nw_inc_nui"
#include "color"

const string PL_DB        = "partyloot";
const int    PL_TIMEOUT   = 30;     // seconds before non-responders auto-Pass
const int    PL_DEFAULT_THRESHOLD = 10000;

// Choice codes stored per participant in "pl_choice".
const int PL_PENDING = 0;
const int PL_NEED    = 1;
const int PL_GREED   = 2;
const int PL_PASS    = 3;

// Forward declaration (defined in the item-description section below).
string PL_Comma(int n);

// ---------------------------------------------------------------------------
// Settings helpers
// ---------------------------------------------------------------------------

int PL_GetThreshold(object oLeader)
{
    int t = GetCampaignInt(PL_DB, "threshold", oLeader);
    return (t > 0) ? t : PL_DEFAULT_THRESHOLD;
}

int PL_IsDisabled(object oLeader)
{
    return GetCampaignInt(PL_DB, "disabled", oLeader);
}

int PL_IsOptedOut(object oPC)
{
    return GetCampaignInt(PL_DB, "optout", oPC);
}

string PL_SettingsText(object oLeader)
{
    if (PL_IsDisabled(oLeader))
        return "Party loot rolls are currently DISABLED by the party leader.";
    return "Party loot rolls: ENABLED. Minimum item value to trigger a roll: "
           + PL_Comma(PL_GetThreshold(oLeader)) + " gp.";
}

// Green server message to every PC in the faction (the whole party).
void PL_BroadcastSettings(object oAnyMember)
{
    object oLeader = GetFactionLeader(oAnyMember);
    string sMsg = ColorString(PL_SettingsText(oLeader), COLOR_GREEN);

    object oM = GetFirstFactionMember(oAnyMember, TRUE);
    while (GetIsObjectValid(oM))
    {
        SendMessageToPC(oM, sMsg);
        oM = GetNextFactionMember(oAnyMember, TRUE);
    }
}

// ---------------------------------------------------------------------------
// NUI window
// ---------------------------------------------------------------------------

string PL_ChoiceLabel(int nChoice)
{
    switch (nChoice)
    {
        case PL_NEED:  return "Need";
        case PL_GREED: return "Greed";
        case PL_PASS:  return "Pass";
    }
    return "waiting...";
}

// Build the "who has rolled" panel text from the roster stored on oItem.
string PL_ResultsText(object oItem)
{
    string s = "";
    int nCount = GetLocalInt(oItem, "pl_count");
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
        if (!GetIsObjectValid(oP)) continue;
        int nChoice = GetLocalInt(oP, "pl_choice");
        string sLine = GetName(oP) + " - ";
        if (nChoice == PL_PENDING)
            sLine += "deciding...";
        else if (nChoice == PL_PASS)
            sLine += "Pass";
        else
            sLine += PL_ChoiceLabel(nChoice) + " (" + IntToString(GetLocalInt(oP, "pl_roll")) + ")";
        s += sLine + "\n";
    }
    return s;
}

// ---------------------------------------------------------------------------
// Item description (type / value / grouped properties)
// ---------------------------------------------------------------------------

// Format an integer with thousands separators, e.g. 1234567 -> "1,234,567".
string PL_Comma(int n)
{
    if (n < 0) return "-" + PL_Comma(-n);
    string s = IntToString(n);
    int len = GetStringLength(s);
    string out = "";
    int i;
    for (i = 0; i < len; i++)
    {
        if (i > 0 && ((len - i) % 3) == 0) out += ",";
        out += GetSubString(s, i, 1);
    }
    return out;
}

// Readable base-item type. For armor, the weight class (from base AC) is the
// type, since baseitems.Name only says "Armor".
string PL_BaseItemName(object oItem)
{
    int nBase = GetBaseItemType(oItem);

    if (nBase == BASE_ITEM_ARMOR)
    {
        int nAC = GetItemACValue(oItem);
        if (nAC <= 0) return "Clothing";
        if (nAC <= 3) return "Light Armor";
        if (nAC <= 5) return "Medium Armor";
        return "Heavy Armor";
    }

    string sName;
    string sRef = Get2DAString("baseitems", "Name", nBase);
    if (sRef != "") sName = GetStringByStrRef(StringToInt(sRef));
    if (sName == "") sName = Get2DAString("baseitems", "label", nBase);
    if (sName == "") sName = "Item type #" + IntToString(nBase);
    return sName;
}

// Readable property *type* name (the group header), e.g. "Skill Bonus".
// Mirrors forge_inc.nss::ForgePropName's type-name lookup (kept inline to avoid
// pulling forge_inc -- and its itemprocs conflict -- into the OnAcquire path).
string PL_PropTypeName(int nType)
{
    string sName;
    string sRef = Get2DAString("itempropdef", "GameStrRef", nType);
    if (sRef != "") sName = GetStringByStrRef(StringToInt(sRef));
    if (sName == "") sName = "Property #" + IntToString(nType);
    return sName;
}

// Readable subtype + magnitude for one property (no type prefix), e.g.
// "Lore +5" or "Fire 25%". Mirrors the subtype/cost portions of ForgePropName.
string PL_PropDetail(itemproperty ip)
{
    int iTyp = GetItemPropertyType(ip);
    string sDetail = "";

    int iSubTyp = GetItemPropertySubType(ip);
    if (iSubTyp >= 0)
    {
        string sSubRes = Get2DAString("itempropdef", "SubTypeResRef", iTyp);
        if (sSubRes != "")
        {
            string sSubRef = Get2DAString(sSubRes, "Name", iSubTyp);
            string sSub = "";
            if (sSubRef != "") sSub = GetStringByStrRef(StringToInt(sSubRef));
            if (sSub == "") sSub = IntToString(iSubTyp);
            sDetail = sSub;
        }
    }

    int iCostTab = GetItemPropertyCostTable(ip);
    if (iCostTab >= 0)
    {
        string sCostRes = Get2DAString("iprp_costtable", "Name", iCostTab);
        if (sCostRes != "")
        {
            string sCostRef = Get2DAString(sCostRes, "Name", GetItemPropertyCostTableValue(ip));
            string sCost = "";
            if (sCostRef != "") sCost = GetStringByStrRef(StringToInt(sCostRef));
            if (sCost != "") sDetail += (sDetail == "" ? "" : " ") + sCost;
        }
    }

    if (sDetail == "") sDetail = "-";
    return sDetail;
}

// All of an item's properties, grouped under their type name. One-time build,
// so the per-type 2da lookups (only for types actually present) are acceptable.
string PL_PropsGrouped(object oItem)
{
    string sOut = "";
    int t;
    for (t = 0; t <= 87; t++)        // ITEM_PROPERTY_* span 0..87
    {
        string sGroup = "";
        itemproperty ip = GetFirstItemProperty(oItem);
        while (GetIsItemPropertyValid(ip))
        {
            if (GetItemPropertyType(ip) == t)
                sGroup += "  - " + PL_PropDetail(ip) + "\n";
            ip = GetNextItemProperty(oItem);
        }
        if (sGroup != "")
            sOut += PL_PropTypeName(t) + ":\n" + sGroup;
    }
    if (sOut == "") sOut = "  (none)\n";
    return sOut;
}

// The info panel text. Unidentified items reveal ONLY their type.
string PL_ItemInfoText(object oItem, int bIdentified)
{
    string sType = PL_BaseItemName(oItem);
    if (!bIdentified)
        return "Type: " + sType + "\n\nThis item is UNIDENTIFIED.";

    return "Type: " + sType + "\n"
         + "Value: " + PL_Comma(GetGoldPieceValue(oItem)) + " gp\n\n"
         + "Properties:\n" + PL_PropsGrouped(oItem);
}

json PL_BuildLayout(object oItem)
{
    int bId = GetIdentified(oItem);
    string sHeader = bId ? GetName(oItem) : "Unidentified " + PL_BaseItemName(oItem);

    // Button row: Need / Greed / Pass. Only NuiId'd elements send events.
    json jButtons = JsonArray();
    jButtons = JsonArrayInsert(jButtons, NuiId(NuiButton(JsonString("Need")),  "btn_need"));
    jButtons = JsonArrayInsert(jButtons, NuiId(NuiButton(JsonString("Greed")), "btn_greed"));
    jButtons = JsonArrayInsert(jButtons, NuiId(NuiButton(JsonString("Pass")),  "btn_pass"));

    json jCol = JsonArray();
    jCol = JsonArrayInsert(jCol, NuiLabel(JsonString(sHeader),
                                          JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_TOP)));
    // Static item info (type / value / grouped properties), scrollable.
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiText(JsonString(PL_ItemInfoText(oItem, bId)),
                                                   TRUE, NUI_SCROLLBARS_AUTO), 230.0));
    jCol = JsonArrayInsert(jCol, NuiLabel(NuiBind("pl_timer"),
                                          JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_TOP)));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiText(NuiBind("pl_results"), TRUE, NUI_SCROLLBARS_AUTO), 110.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jButtons), 40.0));

    json jRoot = NuiCol(jCol);

    return NuiWindow(jRoot,
                     JsonString("Party Loot Roll"),
                     NuiRect(-1.0, -1.0, 440.0, 540.0),
                     JsonBool(FALSE),   // resizable
                     JsonBool(FALSE),   // collapsed (disable collapsing)
                     JsonBool(FALSE),   // closable: no [x] -- must answer
                     JsonBool(FALSE),   // transparent
                     JsonBool(FALSE));  // border
}

// Push the live results + countdown into one open participant's window.
void PL_RefreshWindow(object oPC, object oItem, int nRemaining)
{
    int nTok = GetLocalInt(oPC, "pl_token");
    if (nTok == 0) return;   // window already closed (they responded)
    NuiSetBind(oPC, nTok, "pl_results", JsonString(PL_ResultsText(oItem)));
    NuiSetBind(oPC, nTok, "pl_timer",
               JsonString("Time remaining: " + IntToString(nRemaining) + "s"));
}

void PL_RefreshAll(object oItem, int nRemaining)
{
    int nCount = GetLocalInt(oItem, "pl_count");
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
        if (GetIsObjectValid(oP)) PL_RefreshWindow(oP, oItem, nRemaining);
    }
}

void PL_OpenWindow(object oPC, object oItem)
{
    int nTok = NuiCreate(oPC, PL_BuildLayout(oItem), "partyloot", "pl_nui_evt");
    SetLocalInt(oPC, "pl_token", nTok);
    SetLocalObject(oPC, "pl_item", oItem);
    NuiSetBind(oPC, nTok, "pl_results", JsonString(PL_ResultsText(oItem)));
    NuiSetBind(oPC, nTok, "pl_timer",
               JsonString("Time remaining: " + IntToString(PL_TIMEOUT) + "s"));
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

void PL_Cleanup(object oItem)
{
    int nCount = GetLocalInt(oItem, "pl_count");
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
        if (GetIsObjectValid(oP))
        {
            int nTok = GetLocalInt(oP, "pl_token");
            if (nTok != 0) NuiDestroy(oP, nTok);
            DeleteLocalInt(oP, "pl_token");
            DeleteLocalInt(oP, "pl_choice");
            DeleteLocalInt(oP, "pl_roll");
            DeleteLocalObject(oP, "pl_item");
        }
        DeleteLocalObject(oItem, "pl_p" + IntToString(i));
    }
    DeleteLocalInt(oItem, "pl_count");
    DeleteLocalInt(oItem, "pl_responded");
    DeleteLocalObject(oItem, "pl_looter");
    // "pl_rolled" / "pl_resolved" are intentionally left set as re-entrancy guards.
}

// Pick the winner of a tier (PL_NEED or PL_GREED): highest roll, ties broken by
// a coin flip as we scan. Returns OBJECT_INVALID if nobody chose that tier.
// Read the winning roll afterwards via GetLocalInt(oWinner, "pl_roll").
object PL_PickWinner(object oItem, int nTier)
{
    object oWinner = OBJECT_INVALID;
    int nBest = -1;
    int nCount = GetLocalInt(oItem, "pl_count");
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
        if (!GetIsObjectValid(oP)) continue;
        if (GetLocalInt(oP, "pl_choice") != nTier) continue;
        int nRoll = GetLocalInt(oP, "pl_roll");
        if (nRoll > nBest || (nRoll == nBest && d2() == 1))
        {
            nBest = nRoll;
            oWinner = oP;
        }
    }
    return oWinner;
}

void PL_Resolve(object oItem, int nSession)
{
    if (!GetIsObjectValid(oItem)) return;
    if (GetLocalInt(oItem, "pl_session") != nSession) return;  // stale callback
    if (GetLocalInt(oItem, "pl_resolved")) return;             // already paid out
    SetLocalInt(oItem, "pl_resolved", 1);

    object oLooter = GetLocalObject(oItem, "pl_looter");

    // Non-responders count as Pass.
    int nCount = GetLocalInt(oItem, "pl_count");
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
        if (GetIsObjectValid(oP) && GetLocalInt(oP, "pl_choice") == PL_PENDING)
            SetLocalInt(oP, "pl_choice", PL_PASS);
    }

    object oWinner = PL_PickWinner(oItem, PL_NEED);
    string sTier = "Need";
    if (!GetIsObjectValid(oWinner))
    {
        oWinner = PL_PickWinner(oItem, PL_GREED);
        sTier = "Greed";
    }
    int nWinRoll = GetIsObjectValid(oWinner) ? GetLocalInt(oWinner, "pl_roll") : 0;

    string sItemName = GetName(oItem);

    // Announce to the party (green).
    object oAnnounceFrom = GetIsObjectValid(oLooter) ? oLooter : oWinner;
    string sMsg;
    if (GetIsObjectValid(oWinner))
        sMsg = GetName(oWinner) + " wins " + sItemName + " with a "
             + sTier + " roll of " + IntToString(nWinRoll) + "!";
    else
        sMsg = "Everyone passed on " + sItemName + ". " + GetName(oLooter) + " keeps it.";

    if (GetIsObjectValid(oAnnounceFrom))
    {
        string sGreen = ColorString(sMsg, COLOR_GREEN);
        object oM = GetFirstFactionMember(oAnnounceFrom, TRUE);
        while (GetIsObjectValid(oM))
        {
            SendMessageToPC(oM, sGreen);
            oM = GetNextFactionMember(oAnnounceFrom, TRUE);
        }
    }

    // Transfer the item if the winner is not the current holder (the looter).
    // The "pl_rolled" guard is copied with the item (bCopyVars=TRUE) so the
    // winner re-acquiring the copy does not start a fresh roll.
    if (GetIsObjectValid(oWinner) && oWinner != oLooter)
    {
        CopyItem(oItem, oWinner, TRUE);
        DestroyObject(oItem);
    }

    PL_Cleanup(oItem);
}

// ---------------------------------------------------------------------------
// Response handling (called from pl_nui_evt)
// ---------------------------------------------------------------------------

void PL_Record(object oPC, int nChoice)
{
    object oItem = GetLocalObject(oPC, "pl_item");
    if (!GetIsObjectValid(oItem)) return;
    if (GetLocalInt(oItem, "pl_resolved")) return;
    if (GetLocalInt(oPC, "pl_choice") != PL_PENDING) return;  // already answered

    SetLocalInt(oPC, "pl_choice", nChoice);
    if (nChoice == PL_NEED || nChoice == PL_GREED)
        SetLocalInt(oPC, "pl_roll", d100());

    // Close this player's window.
    int nTok = GetLocalInt(oPC, "pl_token");
    if (nTok != 0)
    {
        NuiDestroy(oPC, nTok);
        SetLocalInt(oPC, "pl_token", 0);
    }

    int nResponded = GetLocalInt(oItem, "pl_responded") + 1;
    SetLocalInt(oItem, "pl_responded", nResponded);

    // Update the still-open windows so deciders see live results.
    PL_RefreshAll(oItem, PL_TIMEOUT);

    if (nResponded >= GetLocalInt(oItem, "pl_count"))
        PL_Resolve(oItem, GetLocalInt(oItem, "pl_session"));
}

// ---------------------------------------------------------------------------
// Trigger (called from acquireditem_tag.nss)
// ---------------------------------------------------------------------------

void PL_OnItemAcquired()
{
    object oItem = GetModuleItemAcquired();
    object oPC   = GetModuleItemAcquiredBy();

    if (!GetIsObjectValid(oItem)) return;          // gold has no item object
    if (!GetIsPC(oPC)) return;
    if (GetLocalInt(oItem, "pl_rolled")) return;   // already contested once

    // Source filter: ignore store purchases and PC-to-PC trades.
    object oFrom = GetModuleItemAcquiredFrom();
    if (GetIsObjectValid(oFrom) &&
        (GetObjectType(oFrom) == OBJECT_TYPE_STORE ||
         GetIsPC(oFrom) ||
         // Pickpocket: item taken from a *living* creature. Corpse/boss loot
         // comes from a dead body (still passes -> still rolls); this only
         // suppresses stealing from a creature that's still up, which is an
         // individual skill contest and not party-contested loot.
         (GetObjectType(oFrom) == OBJECT_TYPE_CREATURE && !GetIsDead(oFrom))))
        return;

    // GetGoldPieceValue returns 1 for unidentified items, so defer the threshold
    // check for them - we'll re-check after the lore step if identification succeeds.
    int bWasUnidentified = !GetIdentified(oItem);

    object oLeader = GetFactionLeader(oPC);
    if (PL_IsDisabled(oLeader)) return;
    if (!bWasUnidentified && GetGoldPieceValue(oItem) < PL_GetThreshold(oLeader)) return;

    object oArea = GetArea(oPC);

    // Build the window roster: non-opted-out in-area PCs.
    // An opted-out looter is excluded (they auto-Pass) but eligible others still roll.
    int nCount = 0;
    int nOtherEligible = 0;
    object oM = GetFirstFactionMember(oPC, TRUE);
    while (GetIsObjectValid(oM))
    {
        if (GetArea(oM) == oArea && !PL_IsOptedOut(oM))
        {
            SetLocalObject(oItem, "pl_p" + IntToString(nCount), oM);
            SetLocalInt(oM, "pl_choice", PL_PENDING);
            nCount++;
            if (oM != oPC) nOtherEligible++;
        }
        oM = GetNextFactionMember(oPC, TRUE);
    }

    // Need at least one non-opted-out party member other than the looter.
    if (nOtherEligible < 1)
    {
        int i;
        for (i = 0; i < nCount; i++)
        {
            object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
            if (GetIsObjectValid(oP)) DeleteLocalInt(oP, "pl_choice");
            DeleteLocalObject(oItem, "pl_p" + IntToString(i));
        }
        return;
    }

    int i;

    // Lore identification: ALL in-area party members attempt to ID an unidentified
    // item - including opted-out players (they contribute lore but get no window).
    // DC uses the item's true (identified) gold value; temporarily identify to read it.
    if (bWasUnidentified)
    {
        SetIdentified(oItem, TRUE);
        int nDC = GetGoldPieceValue(oItem) / 100 + 1;
        SetIdentified(oItem, FALSE);

        int bIdentified = FALSE;
        string sLog = "Party loot - Lore check to identify (DC " + IntToString(nDC) + "):";
        oM = GetFirstFactionMember(oPC, TRUE);
        while (GetIsObjectValid(oM))
        {
            if (GetArea(oM) == oArea)
            {
                int nLore = GetSkillRank(SKILL_LORE, oM);
                int nRoll = d20();
                int nTotal = nRoll + nLore;
                int bPass = (nTotal >= nDC);
                if (bPass) bIdentified = TRUE;
                sLog += "\n  " + GetName(oM) + ": d20(" + IntToString(nRoll) + ") + Lore("
                      + IntToString(nLore) + ") = " + IntToString(nTotal)
                      + (bPass ? " - IDENTIFIED" : " - failed");
            }
            oM = GetNextFactionMember(oPC, TRUE);
        }
        if (bIdentified) SetIdentified(oItem, TRUE);
        else sLog += "\n  No one identified the item; it remains UNIDENTIFIED.";

        // Broadcast the roll log to all in-area party members.
        oM = GetFirstFactionMember(oPC, TRUE);
        while (GetIsObjectValid(oM))
        {
            if (GetArea(oM) == oArea) SendMessageToPC(oM, sLog);
            oM = GetNextFactionMember(oPC, TRUE);
        }

        // If lore identified the item and its value is below threshold, skip the roll.
        if (GetIdentified(oItem) && GetGoldPieceValue(oItem) < PL_GetThreshold(oLeader))
        {
            for (i = 0; i < nCount; i++)
            {
                object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
                if (GetIsObjectValid(oP)) DeleteLocalInt(oP, "pl_choice");
                DeleteLocalObject(oItem, "pl_p" + IntToString(i));
            }
            return;
        }
    }

    int nSession = GetLocalInt(oItem, "pl_session") + 1;
    SetLocalInt(oItem, "pl_session", nSession);
    SetLocalInt(oItem, "pl_rolled", 1);
    SetLocalInt(oItem, "pl_count", nCount);
    SetLocalInt(oItem, "pl_responded", 0);
    SetLocalObject(oItem, "pl_looter", oPC);

    for (i = 0; i < nCount; i++)
    {
        object oP = GetLocalObject(oItem, "pl_p" + IntToString(i));
        PL_OpenWindow(oP, oItem);
    }

    // Resolve at timeout (idempotent; early resolve happens in PL_Record).
    DelayCommand(IntToFloat(PL_TIMEOUT), PL_Resolve(oItem, nSession));
}
