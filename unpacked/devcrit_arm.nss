// devcrit_arm.nss - strip Devastating Critical (Unarmed) / (Creature) from the
// creature running it, keeping the entitlement as a snapshot local.
//
// Roadmap: devcrit-unarmed-save-or-die. Those two feats are the only
// devastating criticals the engine resolves WITHOUT reading the weapon's
// baseitems.2da row, so the blank EpicWeaponDevastatingCriticalFeat column that
// devcrit-roll shipped cannot reach them: a fist build or a clawing monster was
// still rolling the old save-or-die months after the "fix". Possession of the
// feat is the only thing left to take away - see devcrit_inc.nss.
//
// This exists as a script rather than a call inside nw_c2_default9.nss so that
// the OnSpawn handler of every creature in the module does not have to compile
// devcrit_inc's include tree. Same shape as bst_install, which it sits next to.
//
// Called from:
//   nw_c2_default9.nss  - the common OnSpawn, and only for a creature that
//                         actually holds one of the two feats.
// Players are armed from mod_cliententer.nss and re-armed from legfeat_lvl.nss
// (a level-up can hand the feat back).
//
// Idempotent: DevCrit_ArmNoDevCrit does nothing once the feat is gone.

#include "devcrit_inc"

void main()
{
    DevCrit_ArmNoDevCrit(OBJECT_SELF);
}
