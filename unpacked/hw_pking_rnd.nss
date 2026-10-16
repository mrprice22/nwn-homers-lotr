// hw_pking_rnd - Pumpkin King end-of-round: idle skeletons of his army within
// 20m are sent at his foe, then the stock combat round runs. The sacrifice and
// the pumpkin harvest live in hw_pking_dmg (OnDamaged, real-time timers): this
// event only fires on rounds he actually takes.

#include "hw_inc"

void main()
{
    object oKing = OBJECT_SELF;
    object oFoe = GetAttackTarget(oKing);
    if (!GetIsObjectValid(oFoe)) oFoe = GetAttemptedAttackTarget();
    if (!GetIsObjectValid(oFoe))
        oFoe = GetNearestCreature(CREATURE_TYPE_PLAYER_CHAR, PLAYER_CHAR_IS_PC, oKing);

    if (GetIsObjectValid(oFoe))
    {
        int k = 1;
        object oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, k);
        while (GetIsObjectValid(oSk) && GetDistanceBetween(oSk, oKing) <= 20.0)
        {
            if (!GetIsDead(oSk) && GetCommandable(oSk)
                && !GetIsObjectValid(GetAttackTarget(oSk)))
            {
                AssignCommand(oSk, ClearAllActions());
                AssignCommand(oSk, ActionAttack(oFoe));
            }
            oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, ++k);
        }
    }

    ExecuteScript("x2_def_endcombat", oKing);
}
