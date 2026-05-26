//:: mw_jocko_er -- OnEndCombatRound for Jocko (Fighter 30 / Monk 30).
//::
//:: MW_STYLE 0 (Get After It, default):
//::   All-out aggression. Stunning Fist on nearest enemy every round;
//::   standard AI handles attacks.
//::
//:: MW_STYLE 1 (Extreme Ownership):
//::   Bodyguard mode. Finds and attacks whoever is targeting the master;
//::   pulls focus so the master can fight freely. Self only.

const int FEAT_STUN_FIST   = 39;
const int FEAT_KNOCK_DOWN  = 207;

void main()
{
    int nStyle  = GetLocalInt(OBJECT_SELF, "MW_STYLE");
    object oPC  = GetMaster();

    if (nStyle == 1) // Extreme Ownership: attack master's attacker
    {
        if (GetIsObjectValid(oPC))
        {
            object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);
            int n = 1;
            while (GetIsObjectValid(oEnemy))
            {
                if (GetAttackTarget(oEnemy) == oPC)
                {
                    ClearAllActions();
                    ActionAttack(oEnemy);
                    return;
                }
                n++;
                oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, n, CREATURE_TYPE_IS_ALIVE, TRUE);
            }
        }
        // No enemy targeting master -- fall through to standard AI
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    // Style 0 (Get After It): Stunning Fist + standard combat
    object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);
    if (GetIsObjectValid(oEnemy) && GetHasFeat(FEAT_STUN_FIST))
        ActionUseFeat(FEAT_STUN_FIST, oEnemy);

    ExecuteScript("x2_def_endcombat", OBJECT_SELF);
}
