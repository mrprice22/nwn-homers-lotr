// legfeat_reset.nss - admin test tool: reset the speaker's legendary feats.
//
// Rest menu -> [Admin Options] -> "[Admin] Reset my legendary feats". The whole
// Admin Options branch is gated by _cdkey (the admindb whitelist), so this
// script needs no gate of its own - it sits beside grant_lvl60 and is reached
// the same way.
//
// Puts the character back to "never had a legendary feat": feats removed, any
// base-score points we recorded granting subtracted, pick and allotment records
// cleared. The next level-up, rest or login grants a fresh allotment.
//
// Written for repeat use - testing a feat, resetting, and testing the next one
// is the loop this exists to serve, and it stays correct as the feat pool grows
// because it iterates the generated table rather than a hand-written list.
//
// See README.md "Resetting a character's legendary feats".
#include "legfeat_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsPC(oPC)) return;

    int nRemoved = LegFeat_ResetCharacter(oPC);

    if (nRemoved > 0)
        FloatingTextStringOnCreature("Legendary feats reset ("
            + IntToString(nRemoved) + " removed).", oPC, FALSE);
    else
        FloatingTextStringOnCreature(
            "No legendary feats to reset. Allotment cleared.", oPC, FALSE);
}
