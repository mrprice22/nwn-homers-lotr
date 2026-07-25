// code_redeem.nss
// Module OnPlayerChat handler. Players type "Code:<name>" to redeem a code.
// One redemption per CD key per code. Codes can have an expiration date.
//
// To add a new code:
//   1. Add a case to GetCodeExpiration() with its YYYY-MM-DD expiration.
//   2. Add a matching case to ApplyCodeBenefit() that grants the reward.
// Codes are matched case-insensitively.

#include "chisel_inc"

const string CODE_DB     = "coderedeem";
const string CODE_PREFIX = "code:";

// Cumulative XP for character level 60, i.e. the last real row of the
// server's own experience table (hak_2da/exptable.2da, row 59 -> level 60).
// Keep this in sync with that file if the 41-60 curve is ever retuned. It is
// deliberately NOT taken from the retired HGLL accounting, whose total-to-60
// was ~17.5M and bears no relation to the published table.
const int XP_LEVEL_60 = 3581000;

// Returns the expiration date "YYYY-MM-DD" for sCodeLower, or "" if unknown.
string GetCodeExpiration(string sCodeLower)
{
    if (sCodeLower == "freelegendary") return "2026-07-01";
    if (sCodeLower == "defect20260516") return "2026-05-25";
    if (sCodeLower == "first100hours") return "2026-07-01";
    if (sCodeLower == "forgingahead") return "2026-07-15";
    if (sCodeLower == "amuletgift") return "2099-12-31";
    if (sCodeLower == "slottoken") return "2026-08-06";
    if (sCodeLower == "gottahavemoreammo") return "2026-08-08";
    return "";
}

// Apply the reward for sCodeLower to oPC. Return TRUE on success.
int ApplyCodeBenefit(string sCodeLower, object oPC)
{
    if (sCodeLower == "freelegendary")
    {
        // Absolute set: top the character up to exactly level 60 on the
        // published table. Never move XP downwards -- a character who has
        // banked XP past the last table row must not be docked by redeeming.
        if (GetXP(oPC) < XP_LEVEL_60) SetXP(oPC, XP_LEVEL_60);
        return TRUE;
    }
    if (sCodeLower == "defect20260516")
    {
        GiveXPToCreature(oPC, 25000);
        return TRUE;
    }
    if (sCodeLower == "first100hours")
    {
        CreateItemOnObject("rodoffirst100hou", oPC);
        return TRUE;
    }
    if (sCodeLower == "forgingahead")
    {
        int i;
        for (i = 0; i < 3; i++) CreateItemOnObject("forgekey", oPC);
        return TRUE;
    }
    if (sCodeLower == "amuletgift")
    {
        CreateItemOnObject("amuletgift", oPC);
        return TRUE;
    }
    if (sCodeLower == "slottoken")
    {
        CreateItemOnObject("slot_token", oPC);
        return TRUE;
    }
    if (sCodeLower == "gottahavemoreammo")
    {
        CreateItemOnObject("ammoreplicator", oPC);
        return TRUE;
    }
    return FALSE;
}

void EnsureSchema()
{
    sqlquery q = SqlPrepareQueryCampaign(CODE_DB,
        "CREATE TABLE IF NOT EXISTS redemptions (" +
        " code TEXT NOT NULL," +
        " cdkey TEXT NOT NULL," +
        " redeemed_at TEXT NOT NULL DEFAULT (datetime('now'))," +
        " PRIMARY KEY (code, cdkey))");
    SqlStep(q);
}

int IsCodeExpired(string sExpDate)
{
    sqlquery q = SqlPrepareQueryCampaign(CODE_DB,
        "SELECT date('now') > @exp");
    SqlBindString(q, "@exp", sExpDate);
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return FALSE;
}

int HasRedeemed(string sCode, string sCDKey)
{
    sqlquery q = SqlPrepareQueryCampaign(CODE_DB,
        "SELECT 1 FROM redemptions WHERE code = @code AND cdkey = @cdkey");
    SqlBindString(q, "@code", sCode);
    SqlBindString(q, "@cdkey", sCDKey);
    return SqlStep(q);
}

void RecordRedemption(string sCode, string sCDKey)
{
    sqlquery q = SqlPrepareQueryCampaign(CODE_DB,
        "INSERT INTO redemptions (code, cdkey) VALUES (@code, @cdkey)");
    SqlBindString(q, "@code", sCode);
    SqlBindString(q, "@cdkey", sCDKey);
    SqlStep(q);
}

string TrimSpaces(string s)
{
    while (GetStringLength(s) > 0 && GetSubString(s, 0, 1) == " ")
        s = GetSubString(s, 1, GetStringLength(s) - 1);
    while (GetStringLength(s) > 0 &&
           GetSubString(s, GetStringLength(s) - 1, 1) == " ")
        s = GetSubString(s, 0, GetStringLength(s) - 1);
    return s;
}

void main()
{
    object oPC = GetPCChatSpeaker();
    if (!GetIsPC(oPC) && !GetIsDM(oPC)) return;

    string sMsg = GetPCChatMessage();

    // Engraver's Chisel weapon rename: if this PC has a rename pending, this
    // chat line is the new item name -- consume it and never broadcast it.
    // See chisel_inc.nss (dispatched from dmfi_activate / chisel_start).
    if (Chisel_HandleChat(oPC, sMsg))
    {
        SetPCChatMessage("");
        return;
    }

    int iPrefixLen = GetStringLength(CODE_PREFIX);
    if (GetStringLength(sMsg) < iPrefixLen) return;
    if (GetStringLowerCase(GetSubString(sMsg, 0, iPrefixLen)) != CODE_PREFIX)
        return;

    // Don't broadcast the code to the rest of the server.
    SetPCChatMessage("");

    string sCode = TrimSpaces(GetStringLowerCase(
        GetSubString(sMsg, iPrefixLen, GetStringLength(sMsg) - iPrefixLen)));
    if (sCode == "") return;

    EnsureSchema();

    string sExp = GetCodeExpiration(sCode);
    if (sExp == "")
    {
        SendMessageToPC(oPC, "Unknown redemption code.");
        return;
    }

    if (IsCodeExpired(sExp))
    {
        SendMessageToPC(oPC, "That code has expired (was valid until " +
                             sExp + ").");
        return;
    }

    string sCDKey = GetPCPublicCDKey(oPC);
    if (HasRedeemed(sCode, sCDKey))
    {
        SendMessageToPC(oPC, "You have already redeemed that code.");
        return;
    }

    if (!ApplyCodeBenefit(sCode, oPC))
    {
        SendMessageToPC(oPC, "Code redemption failed: no benefit configured.");
        return;
    }

    RecordRedemption(sCode, sCDKey);
    SendMessageToPC(oPC, "Code redeemed successfully!");
}
