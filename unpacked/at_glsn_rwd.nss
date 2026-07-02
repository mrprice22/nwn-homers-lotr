//::///////////////////////////////////////////////
//:: at_glsn_rwd
//:: Gloison's Heirloom — turn-in reward.
//:: Consumes the heirloom and rewards the PC. Gated upstream by
//:: sc_glsn_have, so the item is present when this fires.
//:://////////////////////////////////////////////
#include "boost_inc"
void main()
{
    object oPC   = GetPCSpeaker();
    object oItem = GetItemPossessedBy(oPC, "GloisonsFamilyStone");

    if (GetIsObjectValid(oItem))
        DestroyObject(oItem);

    Boost_GiveXP(oPC, 5000);
    Boost_GiveGold(oPC, 15000);
}
