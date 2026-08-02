// legfeat_lvl.nss — NWNX_ON_LEVEL_UP_AFTER / NWNX_ON_LEVEL_DOWN_AFTER handler
// for Legendary Feats. Subscribed in onmoduleload.nss.
//
// Both directions matter, and they do different things:
//
//   UP to 60   — grant the allotment and open the picker.
//   DOWN below 60, or any class-composition change — LegFeat_EnsureAllotment
//                revokes what the character no longer qualifies for. Death XP
//                loss can take a 60 back to 59, and a legendary feat must not
//                survive that.
//
// Energy drain is not a level loss and never reaches the revoke path — see
// legfeat_inc.nss. This script does not need to know about it.
//
// The picker is opened on a 2-second delay: at _AFTER the engine is still
// finishing the level-up with its own UI on screen, and a NUI window opened
// into that is one the player cannot interact with.

#include "legfeat_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    // Runs in both directions: this is the revoke path as well as the grant.
    int nRemaining = LegFeat_EnsureAllotment(oPC);

    if (LegFeat_TrueLevel(oPC) < LEGFEAT_LEVEL) return;
    if (nRemaining <= 0) return;

    DelayCommand(2.0, ExecuteScript("legfeat_open", oPC));
}
