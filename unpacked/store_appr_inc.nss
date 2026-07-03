// store_appr_inc.nss — Appraise-scaled, per-PC store opening.
//
// A store's MaxBuyPrice (the cap on the gold it will pay a player for any one
// item) lives on the shared store object, so scaling it in place would leak one
// player's Appraise bonus to everyone else shopping the same store. Instead,
// OpenStoreAppr opens a throwaway COPY of the store whose cap is scaled by the
// opening player's Appraise — fully per-player, nothing shared. The copy is
// destroyed when the player closes it (store_appr_cls on STORE_ON_CLOSE), with
// a delayed fallback in case the close event is missed.
//
// Use this in place of OpenStore(...) / gplotAppraiseOpenStore(...) in the
// conversation/opener scripts of stores that BUY from players. On capped stores it
// raises the buy cap by the opener's Appraise, then stacks the premium 2x gold boost
// (Boost_Mult) multiplicatively on top, and sends the player a cyan breakdown of the
// result; the store is otherwise opened exactly as before. bAppraisePricing mirrors
// how the original opener
// opened the store, so existing buy/sell pricing is preserved:
//   - openers that used plain OpenStore  -> OpenStoreAppr(oStore, oPC)        (FALSE)
//   - openers that used gplotAppraiseOpenStore -> OpenStoreAppr(o, oPC, TRUE) (gplot)
// Uncapped stores (MaxBuyPrice -1) open normally with no copy.

#include "appraise_inc"
#include "boost_inc"    // Boost_Mult(oPC) -> 2 when the premium boost is active, else 1
#include "color"        // ColorString + COLOR_LIGHT_BLUE (the module's cyan token)
#include "nw_i0_plot"   // gplotAppraiseOpenStore — preserves stock store pricing

// Thousands-separated gold string, standard-currency style: 196000 -> "196,000".
// Values passed here are non-negative store caps.
string GoldStr(int n)
{
    string s = IntToString(n);
    string sOut = "";
    int nLen = GetStringLength(s), i;
    for (i = 0; i < nLen; i++)
    {
        if (i > 0 && (nLen - i) % 3 == 0) sOut += ",";
        sOut += GetSubString(s, i, 1);
    }
    return sOut;
}

// Cyan one-line breakdown of the buy-from-player cap the player just got, sent on
// every merchant open. nBase <= 0 means the store is uncapped (unlimited buy price);
// Appraise and the boost don't apply there, so report it as unlimited.
void StoreApprReport(object oPC, int nBase, int nApprBonus, int nMult, int nFinal)
{
    string sMsg;
    if (nBase <= 0)
    {
        sMsg = "[Merchant] Buy-from-you cap: unlimited (no per-item limit).";
    }
    else
    {
        int nPct = nApprBonus * 100 / nBase;
        string sBoost = (nMult > 1) ? " | Premium x2 ACTIVE" : "";
        sMsg = "[Merchant] Buy-from-you cap: base " + GoldStr(nBase)
             + " | Appraise " + IntToString(AppraiseCheck(oPC))
             + " (+" + IntToString(nPct) + "%)" + sBoost
             + " | Total: " + GoldStr(nFinal) + " gp";
    }
    SendMessageToPC(oPC, ColorString(sMsg, COLOR_LIGHT_BLUE));
}

// Open oStore for oPC using whichever stock open call the original opener used.
void StoreOpenAs(object oStore, object oPC, int bAppraisePricing)
{
    if (bAppraisePricing)
        gplotAppraiseOpenStore(oStore, oPC);
    else
        OpenStore(oStore, oPC);
}

void OpenStoreAppr(object oStore, object oPC, int bAppraisePricing = FALSE)
{
    if (GetObjectType(oStore) != OBJECT_TYPE_STORE || !GetIsPC(oPC))
        return;

    int nBase = GetStoreMaxBuyPrice(oStore);
    // -1 = uncapped: nothing to raise, open the real store directly.
    if (nBase <= 0)
    {
        StoreApprReport(oPC, nBase, 0, 1, nBase);
        StoreOpenAs(oStore, oPC, bAppraisePricing);
        return;
    }

    // Per-PC throwaway copy. bCopyLocalState=TRUE carries the live store's
    // inventory, local vars and event scripts (e.g. clean_store2 OnOpen).
    object oCopy = CopyObject(oStore, GetLocation(oStore), OBJECT_INVALID, "", TRUE);
    if (!GetIsObjectValid(oCopy))
    {
        // Copy failed — never deny the player their store; open the original.
        StoreOpenAs(oStore, oPC, bAppraisePricing);
        return;
    }

    // Raise this player's cap. Appraise adds +0 (no investment) up to +100% (double)
    // at an Appraise check of 65; the premium 2x boost then STACKS multiplicatively on
    // top (up to 4x base with both maxed). Merchant sales were previously the one gold
    // path the boost never touched — this is the 2x-gold-defect fix.
    int nApprBonus = AppraiseBonusScaled(oPC, nBase);   // 0 .. nBase
    int nMult      = Boost_Mult(oPC);                   // 1 or 2
    int nFinal     = (nBase + nApprBonus) * nMult;
    SetStoreMaxBuyPrice(oCopy, nFinal);
    StoreApprReport(oPC, nBase, nApprBonus, nMult, nFinal);
    SetLocalInt(oCopy, "STORE_APPR_COPY", TRUE);
    SetEventScript(oCopy, EVENT_SCRIPT_STORE_ON_CLOSE, "store_appr_cls");
    StoreOpenAs(oCopy, oPC, bAppraisePricing);
    // Fallback cleanup if the close event never fires (e.g. client disconnect).
    DestroyObject(oCopy, 1800.0);
}
