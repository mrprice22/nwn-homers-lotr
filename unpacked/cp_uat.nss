// cp_uat -- Crash Party: UAT helper. Control-room placeable, OnUsed.
//
// Reports the charges left on every cp_* item in the PRESSER'S OWN pack, then
// burns each one down to CP_UAT_LEFT so the break path can be exercised in
// seconds instead of four hundred activations.
//
// ## Why a lever and not a CLI
//
// Charges are LocalInts on the item object, serialised into the player's .bic.
// Nothing host-side can reach them -- bin/crash-party-db.py deliberately stops at
// the database, because "no server-side thing removes a player's charges" is a
// promise the event makes, not an oversight. An in-game lever run BY the admin
// ON the admin's own items is the only honest way to test expiry.
//
// ## Scope, and why it is drawn this tightly
//
// It only ever touches GetLastUsedBy()'s own inventory. It cannot be pointed at
// another player, and there is no variant of it that can. If this ever needs to
// affect somebody else's items, the answer is no.
//
// Showing the count is fine HERE and nowhere else: this is behind the
// Admin_CanAdmin gate in a room players cannot reach. Never surface a charge
// count to a player -- see cp_inc.nss.

#include "cp_dm_inc"

const int CP_UAT_LEFT = 3;

void main()
{
    object oPC = GetLastUsedBy();
    if (!CP_DmGate(oPC)) return;

    string sOut = COLOR_YELLOW + "-- CRASH PARTY UAT: your own cp_* items --" + COLOR_END + "\n";
    int nFound = 0;
    int i;

    for (i = 0; i < CP_ITEM_COUNT; i++)
    {
        string sRes  = CP_ItemResRef(i);
        object oItem = GetItemPossessedBy(oPC, sRes);
        if (!GetIsObjectValid(oItem)) continue;

        nFound++;
        int nMax  = CP_ItemCharges(i);
        int bInit = GetLocalInt(oItem, CP_INIT_VAR);
        int nLeft = bInit ? GetLocalInt(oItem, CP_USES_VAR) : nMax;

        sOut += "  " + GetName(oItem) + ": " + IntToString(nLeft)
             + " / " + IntToString(nMax) + (bInit ? "" : " (unused)") + "\n";

        // Force the counter into the initialised state at a low value, so the
        // very next few activations walk it to zero and fire the break message.
        SetLocalInt(oItem, CP_INIT_VAR, TRUE);
        SetLocalInt(oItem, CP_USES_VAR, CP_UAT_LEFT);
    }

    if (nFound == 0)
    {
        SendMessageToPC(oPC,
            "You are not carrying any Crash Party items. Turn the party on and "
            + "walk into the Well of Eru to be issued a set.");
        return;
    }

    sOut += "\nAll " + IntToString(nFound) + " burned down to "
          + IntToString(CP_UAT_LEFT) + " charge(s). Activate to watch them break.";
    SendMessageToPC(oPC, sOut);
}
