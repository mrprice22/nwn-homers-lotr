// lw_evt.nss - NUI event handler for the Loot Wishlist window (lo-wishlist).
// Registered per-window via the sEventScript arg of NuiCreate in lw_nui.
//
// Every element id is re-validated here: a base row must be a loot base
// (LootD_BaseCat >= 0), so a client cannot store an arbitrary row.

#include "lw_nui"

void main()
{
    if (NuiGetEventType() != "click") return;   // buttons send "click"

    object oPC   = NuiGetEventPlayer();
    string sElem = NuiGetEventElement();

    if (sElem == "bclose")
    {
        LW_Close(oPC);
        return;
    }

    // "c<n>" - show category n. Browsing is allowed in combat; changes are not.
    if (GetStringLeft(sElem, 1) == "c")
    {
        int nCat = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));
        if (nCat < 0 || nCat >= LOOTD_CAT_COUNT) return;
        SetLocalInt(oPC, LW_CAT, nCat + 1);
        LW_Open(oPC);
        return;
    }

    if (GetIsInCombat(oPC))
    {
        SendMessageToPC(oPC, "You cannot change your loot wishlist in combat.");
        return;
    }

    if (sElem == "bclear")
    {
        Loot_WishClear(oPC);
        SendMessageToPC(oPC, "Your loot wishlist is now empty.");
    }
    else if (sElem == "bauto")
    {
        int bOn = !Loot_WishAutoOn(oPC);
        Loot_WishSetAuto(oPC, bOn);
        SendMessageToPC(oPC, bOn
            ? "Auto is on: with an empty wishlist, your loot leans toward the weapons your feats favour."
            : "Auto is off: with an empty wishlist, your loot is plain random.");
    }
    else if (GetStringLeft(sElem, 1) == "b")
    {
        int nBase = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));
        if (LootD_BaseCat(nBase) < 0) return;
        if (Loot_WishHas(oPC, nBase))
        {
            Loot_WishRemove(oPC, nBase);
            SendMessageToPC(oPC, LootD_BaseName(nBase) + " removed from your loot wishlist.");
        }
        else if (Loot_WishCount(oPC) >= LOOTD_WISH_MAX)
        {
            SendMessageToPC(oPC, "Your loot wishlist is full (" + IntToString(LOOTD_WISH_MAX)
                + " item types). Remove one first.");
            return;
        }
        else
        {
            Loot_WishAdd(oPC, nBase);
            SendMessageToPC(oPC, LootD_BaseName(nBase) + " added to your loot wishlist.");
        }
    }
    else
        return;

    LW_Open(oPC);
}
