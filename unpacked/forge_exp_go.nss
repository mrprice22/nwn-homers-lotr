//::///////////////////////////////////////////////
//:: forge_exp_go -- "Expand property slot" reply Action (Forge of Wonders).
//::
//:: A direct one-tap forge service (like the enchant options): binds one Rune of
//:: Expansion from the PC's pack into the item on the anvil, +1 permanent property
//:: slot up to FORGE_TOKEN_MAX_SLOTS, and the smith speaks the outcome. Consumes a
//:: rune ONLY on a real bind - a no-op (no item / maxed / no rune in pack) just
//:: explains and keeps the rune. Gated in the dlg by isitemonanvil. The reply
//:: loops back to the forge menu. See forge_inc.nss ForgeExpandDo.
//:://////////////////////////////////////////////
#include "forge_inc"

void main()
{
    ForgeExpandDo(GetPCSpeaker());
}
