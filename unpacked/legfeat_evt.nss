// legfeat_evt.nss - NUI event handler for the Legendary Feats picker.
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

    // "i<index>" - show that feat in the detail pane.
    //
    // ONE BIND IS UPDATED. THE WINDOW IS NOT REBUILT. Reopening the picker here
    // was correct but felt broken: it discarded the list's scroll position, and
    // the client's own cache of that position made it inconsistent - some
    // clicks snapped back to the top of the pool, some restored the last
    // remembered offset. Only the pane's contents change, so the list stays put.
    if (GetStringLeft(sElem, 1) == "i")
    {
        LegFeat_Select(oPC,
            StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1)));
        LegFeat_RefreshDetail(oPC);
        return;
    }

    // "t<index>" - take the feat at that picker index.
    if (GetStringLeft(sElem, 1) != "t") return;
    int nIndex = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));

    if (!LegFeat_Take(oPC, nIndex))
    {
        // Every rejection is a state the window should already have prevented
        // (no picks left, prerequisite unmet, feat already held, not level 60,
        // polymorphed), so say which - and say the RIGHT one.
        //
        // These branches mirror LegFeat_Take's own rejection order exactly. They
        // used to stop after two, so a refusal for being under level 60 or for
        // being polymorphed fell through to "You already have that legendary
        // feat." - a message that sends the player looking for a feat they do
        // not have.
        if (LegFeat_TrueLevel(oPC) < LEGFEAT_LEVEL)
            SendMessageToPC(oPC, "Legendary feats are chosen at level "
                + IntToString(LEGFEAT_LEVEL) + ".");
        else if (LegFeat_Remaining(oPC) <= 0)
            SendMessageToPC(oPC, "You have no legendary feat picks remaining.");
        else if (LegFeat_HasPick(oPC, LegFeat_IdAt(nIndex))
                 || GetHasFeat(LegFeat_IdAt(nIndex), oPC))
            SendMessageToPC(oPC, "You already have that legendary feat.");
        else if (LegFeat_IsPolymorphed(oPC))
            SendMessageToPC(oPC, "You cannot choose a legendary feat while "
                + "polymorphed. Return to your own shape and try again.");
        else
            // The FULL measured requirement, clause by clause - this is the one
            // surface with no width limit, and it lands in the chat log where
            // the player can quote it back. Naming which clause failed is the
            // whole of roadmap legendary-feat-prereq-defect-1.
            SendMessageToPC(oPC, LegFeat_NameAt(nIndex) + " requires: "
                + LegFeat_PrereqStatusAt(oPC, nIndex) + ".");
        return;
    }

    SendMessageToPC(oPC, "Legendary feat gained: " + LegFeat_NameAt(nIndex) + ".");

    // Rebuild: the taken row becomes a plain line and the header count drops.
    // Closing outright when the last pick is spent would hide the result, so the
    // window stays up and the player closes it.
    LegFeat_Open(oPC);
}
