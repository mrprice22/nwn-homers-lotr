// legfeat_evt.nss — NUI event handler for the Legendary Feats picker.
// Registered per-window via the sEventScript arg of NuiCreate in legfeat_nui.
#include "legfeat_nui"

void main()
{
    if (NuiGetEventType() != "click") return;   // buttons send "click"

    object oPC   = NuiGetEventPlayer();
    string sElem = NuiGetEventElement();

    if (sElem == "bclose")
    {
        LegFeat_Close(oPC);
        return;
    }

    // "t<index>" — take the feat at that picker index.
    if (GetStringLeft(sElem, 1) != "t") return;
    int nIndex = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));

    if (!LegFeat_Take(oPC, nIndex))
    {
        // Every rejection is a state the window should already have prevented
        // (no picks left, prerequisite unmet, feat already held, not level 60),
        // so say which.
        if (LegFeat_Remaining(oPC) <= 0)
            SendMessageToPC(oPC, "You have no legendary feat picks remaining.");
        else if (!LegFeat_MeetsPrereq(oPC, nIndex))
            SendMessageToPC(oPC, LegFeat_NameAt(nIndex) + " requires: "
                + LegFeat_PrereqAt(nIndex) + ".");
        else
            SendMessageToPC(oPC, "You already have that legendary feat.");
        return;
    }

    SendMessageToPC(oPC, "Legendary feat gained: " + LegFeat_NameAt(nIndex) + ".");

    // Rebuild: the taken row becomes a plain line and the header count drops.
    // Closing outright when the last pick is spent would hide the result, so the
    // window stays up and the player closes it.
    LegFeat_Open(oPC);
}
