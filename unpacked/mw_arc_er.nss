//:: mw_arc_er -- OnEndCombatRound for Peterson (Wizard).
//::
//:: MW_STYLE 0 (Calculated, default):
//::   Ward self with Epic Warding before engaging offensively.
//::   Then layer in epic nukes and let x2 AI handle regular spells.
//::
//:: MW_STYLE 1 (Aggressive):
//::   Skip the warding step; lead with epic nukes immediately.
//::   x2 AI handles regular memorized spells afterward.

const int FEAT_EPIC_WARDING  = 990;
const int FEAT_EPIC_HELLBALL = 876;
const int FEAT_EPIC_RUIN     = 878;
const int FEAT_EPIC_DK       = 875;

void main()
{
    int nStyle  = GetLocalInt(OBJECT_SELF, "MW_STYLE");
    object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY, OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);

    // Style 0: apply Epic Warding on self before going offensive.
    if (nStyle == 0 && GetHasFeat(FEAT_EPIC_WARDING))
    {
        if (!GetHasFeatEffect(FEAT_EPIC_WARDING, OBJECT_SELF))
        {
            ActionUseFeat(FEAT_EPIC_WARDING, OBJECT_SELF);
            // Fall through -- x2 will handle casting in the same round.
        }
    }

    // Both styles: queue an epic nuke if there is a target.
    // ActionUseFeat silently no-ops once the daily slot is expended,
    // so x2_def_endcombat still handles regular memorized spells below.
    if (GetIsObjectValid(oEnemy))
    {
        if (GetHasFeat(FEAT_EPIC_HELLBALL))
            ActionUseFeat(FEAT_EPIC_HELLBALL, oEnemy);
        else if (GetHasFeat(FEAT_EPIC_RUIN))
            ActionUseFeat(FEAT_EPIC_RUIN, oEnemy);
        else if (GetHasFeat(FEAT_EPIC_DK))
            ActionUseFeat(FEAT_EPIC_DK, OBJECT_SELF);
    }

    // Standard associate AI handles memorized spells and basic attacks.
    ExecuteScript("x2_def_endcombat", OBJECT_SELF);
}
