// legfeat_open.nss — open the Legendary Feats picker for OBJECT_SELF.
//
// One entry point for both callers: the level-60 hook (legfeat_lvl, via
// ExecuteScript, where the PC is OBJECT_SELF) and the rest-menu option (a dialog
// action script, where the PC is GetPCSpeaker()). Resolving both here keeps the
// grant logic in one place.
//
// Grants the allotment first if this character has not been given one — that is
// what makes the rest menu a genuine recovery path for a character that reached
// 60 before this feature existed, or dismissed the window.
#include "legfeat_nui"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    if (GetHitDice(oPC) < LEGFEAT_LEVEL)
    {
        SendMessageToPC(oPC, "Legendary feats are chosen at level "
            + IntToString(LEGFEAT_LEVEL) + ".");
        return;
    }

    LegFeat_EnsureAllotment(oPC);
    LegFeat_Open(oPC);
}
