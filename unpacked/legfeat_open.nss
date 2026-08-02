// legfeat_open.nss — open the Legendary Feats picker for OBJECT_SELF.
//
// One entry point for every caller: the level-60 hook (legfeat_lvl) and the
// rest-finished hook (on_mod_rest), both via ExecuteScript on the PC. The
// GetPCSpeaker fallback is kept for a dialog action script, should one ever want
// to open the picker.
//
// Re-derives the allotment first, which both grants it to a character that has
// never had one (reached 60 before this feature existed, or dismissed the
// window) and revokes picks a relevel or a lost level has invalidated.
#include "legfeat_nui"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) oPC = GetPCSpeaker();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    // True level, not GetHitDice: a drained character is still level 60.
    if (LegFeat_TrueLevel(oPC) < LEGFEAT_LEVEL)
    {
        SendMessageToPC(oPC, "Legendary feats are chosen at level "
            + IntToString(LEGFEAT_LEVEL) + ".");
        return;
    }

    LegFeat_EnsureAllotment(oPC);
    LegFeat_Open(oPC);
}
