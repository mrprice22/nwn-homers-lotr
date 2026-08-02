// legfeat_cond.nss — StartingConditional: show a legendary-feat conversation
// node only to a level-60 character.
//
// True level, not GetHitDice: a character with negative levels from energy
// drain is still a level 60 and must not lose access to their own feats.
//
// Writes nothing. It runs every time the conversation is opened, so it stays a
// pure question — the grant and the revoke live in legfeat_respec.
#include "legfeat_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return FALSE;
    return LegFeat_TrueLevel(oPC) >= LEGFEAT_LEVEL;
}
