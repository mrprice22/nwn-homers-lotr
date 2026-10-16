// hw_pking_hb - Pumpkin King heartbeat: out of combat, his skeletons (his
// army, and any fight spawns still about) fall in behind him, and he wanders
// to a random spot in the marsh.

#include "hw_inc"

void main()
{
    object oKing = OBJECT_SELF;
    if (GetIsInCombat(oKing) || GetIsObjectValid(GetAttemptedAttackTarget())) return;

    int n = 1;
    object oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, n);
    while (GetIsObjectValid(oSk))
    {
        if (!GetIsDead(oSk) && !GetIsInCombat(oSk) && GetCommandable(oSk)
            && GetCurrentAction(oSk) != ACTION_FOLLOW)
        {
            AssignCommand(oSk, ClearAllActions());
            AssignCommand(oSk, ActionForceFollowObject(oKing, 2.0 + IntToFloat(Random(5))));
        }
        oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, ++n);
    }

    if (GetCurrentAction(oKing) != ACTION_INVALID) return;
    AssignCommand(oKing, ActionMoveToLocation(HW_RandomMarshSpot(GetArea(oKing))));
}
