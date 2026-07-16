// chisel_inc.nss -- Engraver's Chisel weapon-rename system (roadmap: item-rename).
//
// Flow:
//   1. Player activates the Engraver's Chisel (tag "WeaponChisel", Cast Spell:
//      Unique Power Self Only). dmfi_activate (module OnActivateItem) dispatches
//      to chisel_start, which calls Chisel_Begin(): snapshots the equipped
//      main-hand item on the PC and sets a pending flag.
//   2. The PC's next chat line is intercepted by code_redeem (module
//      OnPlayerChat) via Chisel_HandleChat(): the line is validated, applied
//      with SetName(), one chisel is consumed, and the line is suppressed so
//      the new name is never broadcast.
//
// The new name persists on the item itself (server vault saves the renamed
// item with the character) -- no database needed.
//
// Validation rules: name must be non-empty after trimming, at most
// CHISEL_MAX_LEN characters, and must not contain '<' or '>' (blocks color
// codes and <CUSTOMxxxx> token markup). "cancel" aborts without spending
// the chisel. A failed validation also leaves the chisel unspent -- the
// player just activates it again to retry.

const string CHISEL_TAG     = "WeaponChisel";
const string CHISEL_PENDING = "CHISEL_RENAME_PENDING";
const string CHISEL_TARGET  = "CHISEL_RENAME_TARGET";
const int    CHISEL_MAX_LEN = 40;

// Strip leading/trailing spaces.
string Chisel_Trim(string s)
{
    while (GetStringLength(s) > 0 && GetSubString(s, 0, 1) == " ")
        s = GetSubString(s, 1, GetStringLength(s) - 1);
    while (GetStringLength(s) > 0 &&
           GetSubString(s, GetStringLength(s) - 1, 1) == " ")
        s = GetSubString(s, 0, GetStringLength(s) - 1);
    return s;
}

// Called when the chisel is activated. Snapshots the main-hand item and
// flags the PC so their next chat line becomes the new name.
void Chisel_Begin(object oPC)
{
    object oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC);
    if (!GetIsObjectValid(oWeapon))
    {
        FloatingTextStringOnCreature(
            "You must have a weapon equipped in your main hand to engrave it.",
            oPC, FALSE);
        return;
    }
    SetLocalInt(oPC, CHISEL_PENDING, TRUE);
    SetLocalObject(oPC, CHISEL_TARGET, oWeapon);
    SendMessageToPC(oPC,
        "Engraver's Chisel: speak the new name for '" + GetName(oWeapon) +
        "' in chat (max " + IntToString(CHISEL_MAX_LEN) +
        " characters, no < or >). Say 'cancel' to stop.");
    FloatingTextStringOnCreature(
        "Speak the new name for " + GetName(oWeapon) + " (or 'cancel').",
        oPC, FALSE);
}

// Called from the module OnPlayerChat handler (code_redeem) BEFORE any other
// processing. Returns TRUE when this chat line was a pending rename input and
// has been fully handled -- the caller must then suppress the line
// (SetPCChatMessage("")) and return.
int Chisel_HandleChat(object oPC, string sMsg)
{
    if (!GetLocalInt(oPC, CHISEL_PENDING))
        return FALSE;

    // One-shot: whatever happens below, this line consumes the pending state.
    DeleteLocalInt(oPC, CHISEL_PENDING);
    object oWeapon = GetLocalObject(oPC, CHISEL_TARGET);
    DeleteLocalObject(oPC, CHISEL_TARGET);

    string sName = Chisel_Trim(sMsg);
    if (sName == "" || GetStringLowerCase(sName) == "cancel")
    {
        SendMessageToPC(oPC, "Engraving cancelled. The chisel is unspent.");
        return TRUE;
    }
    if (GetStringLength(sName) > CHISEL_MAX_LEN)
    {
        SendMessageToPC(oPC,
            "Engraving failed: name too long (max " +
            IntToString(CHISEL_MAX_LEN) +
            " characters). Use the chisel again to retry.");
        return TRUE;
    }
    if (FindSubString(sName, "<") != -1 || FindSubString(sName, ">") != -1)
    {
        SendMessageToPC(oPC,
            "Engraving failed: the characters < and > are not allowed. " +
            "Use the chisel again to retry.");
        return TRUE;
    }
    if (!GetIsObjectValid(oWeapon) || GetItemPossessor(oWeapon) != oPC)
    {
        SendMessageToPC(oPC,
            "Engraving failed: you no longer carry the item you targeted. " +
            "Use the chisel again to retry.");
        return TRUE;
    }
    object oChisel = GetItemPossessedBy(oPC, CHISEL_TAG);
    if (!GetIsObjectValid(oChisel))
    {
        SendMessageToPC(oPC,
            "Engraving failed: you no longer carry an Engraver's Chisel.");
        return TRUE;
    }

    string sOld = GetName(oWeapon);
    SetName(oWeapon, sName);
    DestroyObject(oChisel);
    SendMessageToPC(oPC,
        "'" + sOld + "' is now engraved as '" + sName +
        "'. The chisel is spent.");
    FloatingTextStringOnCreature("Engraved: " + sName, oPC, FALSE);
    return TRUE;
}
