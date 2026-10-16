// hw_pking_hb - the Pumpkin King wanders the Dead Marshes.
//
// Out of combat and idle, he picks a random spot in the marsh and walks to it.
// No waypoints: the marsh has hundreds of placeables to pick destinations from,
// and a fixed route would be learned and camped within a day.

#include "hw_inc"

void main()
{
    object oKing = OBJECT_SELF;
    if (GetIsInCombat(oKing) || GetIsObjectValid(GetAttemptedAttackTarget())) return;
    if (GetCurrentAction(oKing) != ACTION_INVALID) return;
    AssignCommand(oKing, ActionMoveToLocation(HW_RandomMarshSpot(GetArea(oKing))));
}
