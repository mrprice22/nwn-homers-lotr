// lootlab_wish.nss - Loot Lab: report the admin's own loot wishlist (Phase 6,
// lo-wishlist): the stored picks, the Auto setting, the Auto tier and its
// weights, and the wishlist chance. Lab rolls pass the admin as beneficiary, so
// "Roll 10" five times is the "the bias shows across about 50 rolls" check.
// Loot Lab action (emotewand.dlg Entry 19). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    string sWish = Loot_WishGet(oPC);
    // Force a fresh Auto list so a feat just added shows up.
    DeleteLocalInt(oPC, LOOT_AUTO_KEY);
    string sAuto = Loot_AutoList(oPC);
    int nTier = GetLocalInt(oPC, LOOT_AUTO_TIER);
    SendMessageToPC(oPC, "Loot Lab wishlist: stored '" + sWish + "' (" + IntToString(Loot_WishCount(oPC))
        + "/" + IntToString(LOOTD_WISH_MAX) + "), Auto " + (Loot_WishAutoOn(oPC) ? "on" : "off")
        + ", chance " + IntToString(LOOTD_WISH_CHANCE) + "/1000.");
    SendMessageToPC(oPC, "Loot Lab wishlist: Auto tier " + IntToString(nTier)
        + (nTier == 1 ? " (focus feats)" : (nTier == 2 ? " (proficiency)" : " (none)"))
        + ", caster " + IntToString(Loot_IsCaster(oPC)) + ": '" + sAuto + "'.");
    SendMessageToPC(oPC, "Loot Lab wishlist: rolls for you draw from '" + Loot_WishCands(oPC) + "'.");
}
