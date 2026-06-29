//:: mw_counter_inc -- Counterspell combat mode (MW_STYLE 3) for caster guides.
//:: Script-driven counter: the guide stands ground and watches; a 1-second
//:: pulse (mw_ctr_pulse) detects an enemy mid-cast, makes an opposed Spellcraft
//:: check, and interrupts the spell on success -- with floating-text cues to the
//:: master telling the party who is being targeted and whether the counter
//:: lands.
//::
//:: This replaces the engine ActionCounterSpell, which was unreliable (it
//:: readied against a single target, frequently expired before the enemy cast,
//:: and let spells slip through) and gave no script callback for success/fail.
//:: The guide's Spellcraft is boosted +30 in MW_ScaleGuide so counters land.

const string MW_CTR_TARGET    = "MW_CTR_TARGET";    // last announced target (on guide)
const string MW_CTR_RUNNING   = "MW_CTR_RUNNING";   // a pulse chain is alive (on guide)
const string MW_CTR_RESOLVING = "MW_CTR_RESOLVING"; // this cast already resolved (on enemy)

int MW_Style3()
{
    return GetLocalInt(OBJECT_SELF, "MW_STYLE") == 3;
}

// Nearest enemy spellcaster (Wiz/Sorc/Cleric/Druid/Bard); fall back to nearest foe.
object MW_PickCounterTarget()
{
    object oNearest = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY,
        OBJECT_SELF, 1, CREATURE_TYPE_IS_ALIVE, TRUE);
    object oFoe = oNearest;
    int k = 1;
    while (GetIsObjectValid(oFoe))
    {
        if (GetLevelByClass(CLASS_TYPE_WIZARD,   oFoe) > 0 ||
            GetLevelByClass(CLASS_TYPE_SORCERER, oFoe) > 0 ||
            GetLevelByClass(CLASS_TYPE_CLERIC,   oFoe) > 0 ||
            GetLevelByClass(CLASS_TYPE_DRUID,    oFoe) > 0 ||
            GetLevelByClass(CLASS_TYPE_BARD,     oFoe) > 0)
            return oFoe;
        k++;
        oFoe = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY,
            OBJECT_SELF, k, CREATURE_TYPE_IS_ALIVE, TRUE);
    }
    return oNearest;
}

// Highest spellcasting class level on a creature -- drives the counter DC.
int MW_CasterLevel(object o)
{
    int n = GetLevelByClass(CLASS_TYPE_WIZARD, o);
    int t;
    t = GetLevelByClass(CLASS_TYPE_SORCERER, o); if (t > n) n = t;
    t = GetLevelByClass(CLASS_TYPE_CLERIC,   o); if (t > n) n = t;
    t = GetLevelByClass(CLASS_TYPE_DRUID,    o); if (t > n) n = t;
    t = GetLevelByClass(CLASS_TYPE_BARD,     o); if (t > n) n = t;
    return n;
}

// Announce a (changed) counter target to the master.
void MW_AnnounceTarget(object oTarget, object oMaster)
{
    if (!GetIsObjectValid(oTarget) || !GetIsObjectValid(oMaster)) return;
    if (GetLocalObject(OBJECT_SELF, MW_CTR_TARGET) == oTarget) return;
    SetLocalObject(OBJECT_SELF, MW_CTR_TARGET, oTarget);
    FloatingTextStringOnCreature(
        GetName(OBJECT_SELF) + " readies a counterspell against " +
        GetName(oTarget) + ".", oMaster, FALSE);
}

// (Re)start the per-second pulse chain if one isn't already running for this guide.
void MW_CtrEnsurePulse()
{
    if (!MW_Style3()) return;
    if (GetLocalInt(OBJECT_SELF, MW_CTR_RUNNING)) return;
    SetLocalInt(OBJECT_SELF, MW_CTR_RUNNING, 1);
    DelayCommand(1.0, ExecuteScript("mw_ctr_pulse", OBJECT_SELF));
}

// OnEndCombatRound entry for style 3: stand ground, look focused, keep the
// targeting cue current, and make sure the detection pulse is running. The
// pulse (mw_ctr_pulse) performs the actual counter.
void MW_CounterspellRound()
{
    object oTarget = MW_PickCounterTarget();
    if (!GetIsObjectValid(oTarget))
    {
        // Nothing to counter -- act normally so the guide isn't left frozen.
        ExecuteScript("x2_def_endcombat", OBJECT_SELF);
        return;
    }

    MW_AnnounceTarget(oTarget, GetMaster());

    // Stand ground and look like we're concentrating; the pulse does the work.
    ClearAllActions();
    SetFacingPoint(GetPosition(oTarget));
    ActionPlayAnimation(ANIMATION_LOOPING_CONJURE1, 1.0, 6.0);

    MW_CtrEnsurePulse();
}

// Per-second detector. Scheduled from mw_ctr_pulse.nss; reschedules itself while
// the guide is still in counterspell mode and near a living master.
void MW_CounterspellPulse()
{
    object oMaster = GetMaster();
    if (!MW_Style3() || !GetIsObjectValid(oMaster) || GetIsDead(OBJECT_SELF) ||
        GetArea(oMaster) != GetArea(OBJECT_SELF))
    {
        // Stop the chain; a later style-3 selection can start a fresh one.
        DeleteLocalInt(OBJECT_SELF, MW_CTR_RUNNING);
        return;
    }

    MW_AnnounceTarget(MW_PickCounterTarget(), oMaster);

    // Scan the nearest enemies for an in-progress cast.
    int i;
    for (i = 1; i <= 5; i++)
    {
        object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY,
            OBJECT_SELF, i, CREATURE_TYPE_IS_ALIVE, TRUE);
        if (!GetIsObjectValid(oEnemy)) break;

        if (GetCurrentAction(oEnemy) != ACTION_CASTSPELL)
        {
            DeleteLocalInt(oEnemy, MW_CTR_RESOLVING); // not casting -- arm for next time
            continue;
        }
        if (GetLocalInt(oEnemy, MW_CTR_RESOLVING)) continue; // this cast already handled
        SetLocalInt(oEnemy, MW_CTR_RESOLVING, 1);

        int nRoll = d20() + GetSkillRank(SKILL_SPELLCRAFT, OBJECT_SELF);
        int nDC   = 15 + MW_CasterLevel(oEnemy);
        if (nRoll >= nDC)
        {
            AssignCommand(oEnemy, ClearAllActions(TRUE)); // interrupt the cast
            FloatingTextStringOnCreature(
                ">> " + GetName(OBJECT_SELF) + " COUNTERS it! (Spellcraft " +
                IntToString(nRoll) + " vs DC " + IntToString(nDC) + ")",
                oMaster, FALSE);
        }
        else
        {
            FloatingTextStringOnCreature(
                ">> " + GetName(OBJECT_SELF) + " fails to counter! (rolled " +
                IntToString(nRoll) + ")", oMaster, FALSE);
        }
    }

    DelayCommand(1.0, ExecuteScript("mw_ctr_pulse", OBJECT_SELF));
}
