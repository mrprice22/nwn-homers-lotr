// legfeat_equip.nss — rebuild CONDITIONAL legendary feat effects on an equip
// change. Subscribed to NWNX_ON_ITEM_EQUIP_AFTER and _UNEQUIP_AFTER in
// onmoduleload.nss.
//
// WHY THIS EXISTS. Most legendary feat effects depend on the feat alone, so
// applying them once at login is enough. Some depend on what the character is
// HOLDING — Legendary Onslaught grants its extra attack for melee and unarmed
// but not for a bow. An effect like that goes stale the moment the player swaps
// weapons, and it goes stale SILENTLY: an archer who switched from a sword keeps
// an extra ranged attack they should not have, and nothing in the log says so.
//
// The whole job is therefore to re-run LegFeat_ApplyAll, which clears the
// LEGFEAT_EFF tag and rebuilds every effect from the pick records. That is
// already the idempotent path used at login, so this adds no new way to be
// wrong — a conditional feat simply asks LegFeat_IsMeleeArmed again.
//
// THE DELAY IS LOAD-BEARING. At _AFTER the engine has not necessarily finished
// moving the item: on unequip in particular the weapon can still read as being
// in the slot, so LegFeat_IsMeleeArmed would answer about the state we are
// leaving rather than the one we are entering. A short delay lets the swap
// settle first. It is not a "just in case" delay; without it, unequipping a bow
// leaves the melee attack unapplied until the next login.

#include "legfeat_inc"
#include "nwnx_events"

const float LEGFEAT_EQUIP_SETTLE = 0.5;

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    // Cheap exit for the overwhelming majority of equip events in the module:
    // this fires on every item swap by every player, and almost nobody holds a
    // legendary feat. LegFeat_ApplyAll would walk the pick table and touch the
    // database; the spent-picks count answers the same question with one read.
    LegFeat_InitDb();
    if (LegFeat_GetSpent(oPC) <= 0) return;

    DelayCommand(LEGFEAT_EQUIP_SETTLE, LegFeat_ApplyAll(oPC));
}
