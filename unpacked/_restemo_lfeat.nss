// _restemo_lfeat.nss — StartingConditional for the rest menu's
// "[Choose your Legendary Feats.]" option (emotewand.dlg).
//
// Shown only while the character has picks to spend, so the option is a
// recovery path — for a window that was dismissed, for a level-60 character
// that predates the feature, and for anyone who wants to spend a second pick
// later. It deliberately does NOT write to the DB: the allotment is granted by
// legfeat_open when the option is actually chosen, so a conditional that runs
// on every rest never changes state.
#include "legfeat_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return FALSE;
    if (GetHitDice(oPC) < LEGFEAT_LEVEL) return FALSE;

    LegFeat_InitDb();
    // Never granted an allotment: this character reached 60 without the picker
    // firing, so offer it.
    if (LegFeat_GetGranted(oPC) <= 0) return TRUE;
    return LegFeat_Remaining(oPC) > 0;
}
