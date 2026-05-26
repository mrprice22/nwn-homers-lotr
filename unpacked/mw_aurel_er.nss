//:: mw_aurel_er -- OnEndCombatRound for Aurelius (Paladin 60).
//::
//:: MW_STYLE 0 (Guardian, default):
//::   Keep the master alive -- cast Heal when master HP drops below 50%.
//::   Otherwise defer to standard AI.
//::
//:: MW_STYLE 1 (Offensive):
//::   Self-heal if own HP is critical; then find and attack any enemy that
//::   is targeting the master -- pull aggro so the master can breathe.
//::   Stays close to the master by attacking his attackers, not random foes.

const int SPELL_CCW     = 31;   // Cure Critical Wounds -- Paladin L4
const int SPELL_CSW     = 35;   // Cure Serious Wounds  -- Paladin L3
const int SPELL_CMW     = 34;   // Cure Moderate Wounds -- Paladin L2

void main()
{
    int nStyle = GetLocalInt(OBJECT_SELF, "MW_STYLE");
    object oPC = GetMaster();

    if (nStyle == 0) // Guardian: prioritize keeping master alive
    {
        if (GetIsObjectValid(oPC))
        {
            int nPCHP    = GetCurrentHitPoints(oPC);
            int nPCMaxHP = GetMaxHitPoints(oPC);
            if (nPCHP < FloatToInt(IntToFloat(nPCMaxHP) * 0.50f))
            {
                if (GetHasSpell(SPELL_CCW, OBJECT_SELF))
                    ActionCastSpellAtObject(SPELL_CCW, oPC);
                else if (GetHasSpell(SPELL_CSW, OBJECT_SELF))
                    ActionCastSpellAtObject(SPELL_CSW, oPC);
                else if (GetHasSpell(SPELL_CMW, OBJECT_SELF))
                    ActionCastSpellAtObject(SPELL_CMW, oPC);
                return;
            }
        }
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    // Style 1 (Offensive): self-heal if critical, then pull aggro
    int nSelfHP    = GetCurrentHitPoints(OBJECT_SELF);
    int nSelfMaxHP = GetMaxHitPoints(OBJECT_SELF);
    if (nSelfHP < FloatToInt(IntToFloat(nSelfMaxHP) * 0.50f))
    {
        if (GetHasSpell(SPELL_CCW, OBJECT_SELF))
        {
            ActionCastSpellAtObject(SPELL_CCW, OBJECT_SELF);
            return;
        }
        else if (GetHasSpell(SPELL_CSW, OBJECT_SELF))
        {
            ActionCastSpellAtObject(SPELL_CSW, OBJECT_SELF);
            return;
        }
    }

    // Find an enemy that is attacking the master and go for them.
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

    // No enemy is targeting master -- attack nearest
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);
}
