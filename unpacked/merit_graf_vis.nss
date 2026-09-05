// merit_graf_vis.nss - StartingConditional for Barliman's "about your mark on
// the Well" branch. Only where it can be acted on: standing in the Well of Eru
// with an open graffiti (301) request. Anywhere else the line is simply absent.
#include "merit_redeem"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) return FALSE;
    if (GetTag(GetArea(oPC)) != "TheWellofEru") return FALSE;
    return Merit_PendingIdFor(GetPCPublicCDKey(oPC), MERIT_REWARD_GRAFFITI) > 0;
}
