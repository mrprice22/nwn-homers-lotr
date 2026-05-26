//:: mw_jung_er -- OnEndCombatRound for Jung (Fighter 20 / Rogue 20 / Shadowdancer 20).
//::
//:: MW_STYLE 0 (Shadow, default):
//::   Attempt to hide (Hide in Plain Sight lets this work mid-combat), then
//::   prioritise attacking enemies that are targeting the master for sneak attacks.
//::
//:: MW_STYLE 1 (Warrior):
//::   Straight open combat via standard AI.

void main()
{
    int nStyle = GetLocalInt(OBJECT_SELF, "MW_STYLE");

    if (nStyle == 1)
    {
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    // Style 0 (Shadow): hide, then attack master's attacker for flanking bonus.
    object oPC = GetMaster();

    // Find an enemy targeting the master (best sneak-attack opportunity).
    object oTarget = OBJECT_INVALID;
    if (GetIsObjectValid(oPC))
    {
        object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);
        int n = 1;
        while (GetIsObjectValid(oEnemy))
        {
            if (GetAttackTarget(oEnemy) == oPC)
            {
                oTarget = oEnemy;
                break;
            }
            n++;
            oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, n, CREATURE_TYPE_IS_ALIVE, TRUE);
        }
    }
    if (!GetIsObjectValid(oTarget))
        oTarget = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);

    if (!GetIsObjectValid(oTarget))
    {
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    ClearAllActions();
    // Hide in Plain Sight -- Shadowdancer can hide even while observed.
    SetActionMode(OBJECT_SELF, ACTION_MODE_STEALTH, 1);
    ActionAttack(oTarget);
}
