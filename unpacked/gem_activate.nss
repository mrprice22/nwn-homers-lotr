// gem_activate.nss - Loot Overhaul Phase 5: set a socket gem into an item.
// Roadmap Socket-system-for-weapons.  OBJECT_SELF = the activating PC; run by
// dmfi_activate (the module OnActivateItem) for any item tagged sgem_*, which
// stashes the gem and its target in gem_item / gem_target first.
//
// The target must be an identified item the PC carries or wears, with an open
// socket the gem fits.  Every refusal leaves both the gem and the item untouched;
// only a successful socketing consumes the gem.  See gem_inc.nss.
#include "gem_inc"

void main()
{
    object oPC = OBJECT_SELF;
    object oGem = GetLocalObject(oPC, "gem_item");
    object oItem = GetLocalObject(oPC, "gem_target");
    DeleteLocalObject(oPC, "gem_item");
    DeleteLocalObject(oPC, "gem_target");
    if (!GetIsObjectValid(oGem) || GetItemPossessor(oGem) != oPC) return;
    if (!GetIsObjectValid(oItem) || GetObjectType(oItem) != OBJECT_TYPE_ITEM
        || GetItemPossessor(oItem) != oPC || oItem == oGem)
    {
        SendMessageToPC(oPC, "Use the gem on an item in your inventory (one you carry or wear).");
        return;
    }
    string sGem = GetName(oGem);
    string sWhy = Gem_Socket(oItem, oGem);
    if (sWhy != "")
    {
        SendMessageToPC(oPC, sWhy);
        return;
    }
    SendMessageToPC(oPC, "You set the " + sGem + " into " + GetName(oItem) + ": "
        + GetLocalString(oItem, "GEM_LAST_MSG") + ". Sockets "
        + IntToString(GetLocalInt(oItem, "SOCKET_FILLED")) + "/"
        + IntToString(GetLocalInt(oItem, "SOCKET_MAX")) + ".");
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_MAGBLUE), oPC);
}
