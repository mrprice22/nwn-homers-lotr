//:: mw_counter_inc -- Counterspell combat mode (MW_STYLE 3) for caster guides.
//:: The guide stands ground and watches; each OnEndCombatRound tags up to 5
//:: nearby enemies as "watched" (MW_CTR_WATCHER). The real interception now
//:: happens inside X2PreSpellCastCode() (see x2_inc_spellhook.nss), which
//:: fires on every spellcast in the module -- this is the only place a
//:: caster's real spell ID/level is knowable, letting the guide make an
//:: opposed Spellcraft check and, on success, spend a same-or-higher-level
//:: memorized slot to silently fizzle the spell (a "real" NWN counterspell,
//:: not just an ActionCounterSpell readied-action approximation).
//::
//:: A 6-second cooldown gates attempts (per guide, regardless of outcome), a
//:: natural 1/20 on the d20 auto-fails/succeeds, and a guide that runs out of
//:: every countable slot falls back to its default (melee-capable) style.
//:: The guide's Spellcraft is boosted a small flat amount in MW_ScaleGuide;
//:: most of the per-guide variance now comes from each blueprint's base rank.

const string MW_CTR_TARGET   = "MW_CTR_TARGET";   // last announced target (on guide)
const string MW_CTR_WATCHER  = "MW_CTR_WATCHER";  // guide watching this enemy (on enemy)
const string MW_CTR_COOLDOWN = "MW_CTR_COOLDOWN"; // attempt cooldown flag (on guide)

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

// Tag the nearest 5 living enemies as "watched" by this guide, so the spell
// hook (MW_CounterspellHook) can recognize their casts cheaply.
void MW_CtrTagWatchers()
{
    int i;
    for (i = 1; i <= 5; i++)
    {
        object oEnemy = GetNearestCreature(CREATURE_TYPE_REPUTATION, REPUTATION_TYPE_ENEMY,
            OBJECT_SELF, i, CREATURE_TYPE_IS_ALIVE, TRUE);
        if (!GetIsObjectValid(oEnemy)) break;
        SetLocalObject(oEnemy, MW_CTR_WATCHER, OBJECT_SELF);
    }
}

// OnEndCombatRound entry for style 3: stand ground, look focused, keep the
// targeting cue current, and (re)tag nearby enemies for the spell hook.
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
    MW_CtrTagWatchers();

    // Stand ground and look like we're concentrating; the spell hook does the work.
    ClearAllActions();
    SetFacingPoint(GetPosition(oTarget));
    ActionPlayAnimation(ANIMATION_LOOPING_CONJURE1, 1.0, 6.0);
}

// Real spell level for nSpellId as cast by nClass, via spells.2da's per-class
// level columns (falls back to Innate when the class column is blank -- this
// covers e.g. Paladin-memorized spells that aren't natively on the Paladin
// list, per x2_inc_craft.nss's own class->column pattern). Returns -1 if
// neither column has a value.
int MW_GetSpellLevel(int nSpellId, int nClass)
{
    string sCol;
    if      (nClass == CLASS_TYPE_BARD)     sCol = "Bard";
    else if (nClass == CLASS_TYPE_CLERIC)   sCol = "Cleric";
    else if (nClass == CLASS_TYPE_DRUID)    sCol = "Druid";
    else if (nClass == CLASS_TYPE_PALADIN)  sCol = "Paladin";
    else if (nClass == CLASS_TYPE_RANGER)   sCol = "Ranger";
    else if (nClass == CLASS_TYPE_WIZARD ||
             nClass == CLASS_TYPE_SORCERER) sCol = "Wiz_Sorc";
    else                                    sCol = "Innate";

    string s = Get2DAString("spells", sCol, nSpellId);
    if (s == "" && sCol != "Innate")
        s = Get2DAString("spells", "Innate", nSpellId);
    if (s == "") return -1;
    return StringToInt(s);
}

//------------------------------------------------------------------------------
// Per-guide countable-slot pools. Each returns a memorized spell ID at the
// lowest level >= nReqLevel that the guide still has an available use of, or
// -1. bHealPass selects between the guide's non-heal pool (tried first) and
// its own emergency-heal pool (tried only if nothing else qualifies).
// SPELL_RESTORATION/SPELL_STONE_TO_FLESH are never included -- those are the
// always-on safety-net cures in mw_hench_hb.nss and must not be drained here.
//------------------------------------------------------------------------------

int MW_Pool_Peterson(object oGuide, int nReqLevel, int bHealPass)
{
    if (bHealPass) return -1; // Peterson has no dedicated heal spells

    if (nReqLevel <= 1 && GetHasSpell(SPELL_MAGIC_MISSILE, oGuide)) return SPELL_MAGIC_MISSILE;
    if (nReqLevel <= 3 && GetHasSpell(SPELL_FIREBALL, oGuide)) return SPELL_FIREBALL;
    if (nReqLevel <= 4 && GetHasSpell(SPELL_STONESKIN, oGuide)) return SPELL_STONESKIN;
    if (nReqLevel <= 5 && GetHasSpell(SPELL_CONE_OF_COLD, oGuide)) return SPELL_CONE_OF_COLD;
    if (nReqLevel <= 6 && GetHasSpell(SPELL_ISAACS_GREATER_MISSILE_STORM, oGuide)) return SPELL_ISAACS_GREATER_MISSILE_STORM;
    if (nReqLevel <= 7 && GetHasSpell(SPELL_FINGER_OF_DEATH, oGuide)) return SPELL_FINGER_OF_DEATH;
    if (nReqLevel <= 8 && GetHasSpell(SPELL_HORRID_WILTING, oGuide)) return SPELL_HORRID_WILTING;
    if (nReqLevel <= 9 && GetHasSpell(SPELL_METEOR_SWARM, oGuide)) return SPELL_METEOR_SWARM;
    return -1;
}

int MW_Pool_Watts(object oGuide, int nReqLevel, int bHealPass)
{
    if (bHealPass)
    {
        if (nReqLevel <= 1 && GetHasSpell(SPELL_CURE_LIGHT_WOUNDS, oGuide)) return SPELL_CURE_LIGHT_WOUNDS;
        if (nReqLevel <= 2 && GetHasSpell(SPELL_CURE_MODERATE_WOUNDS, oGuide)) return SPELL_CURE_MODERATE_WOUNDS;
        if (nReqLevel <= 3 && GetHasSpell(SPELL_CURE_SERIOUS_WOUNDS, oGuide)) return SPELL_CURE_SERIOUS_WOUNDS;
        if (nReqLevel <= 4 && GetHasSpell(SPELL_CURE_CRITICAL_WOUNDS, oGuide)) return SPELL_CURE_CRITICAL_WOUNDS;
        if (nReqLevel <= 5 && GetHasSpell(SPELL_HEALING_CIRCLE, oGuide)) return SPELL_HEALING_CIRCLE;
        if (nReqLevel <= 6 && GetHasSpell(SPELL_HEAL, oGuide)) return SPELL_HEAL;
        return -1;
    }
    if (nReqLevel <= 1 && GetHasSpell(SPELL_DIVINE_FAVOR, oGuide)) return SPELL_DIVINE_FAVOR;
    if (nReqLevel <= 1 && GetHasSpell(SPELL_BLESS, oGuide)) return SPELL_BLESS;
    if (nReqLevel <= 2 && GetHasSpell(SPELL_AID, oGuide)) return SPELL_AID;
    if (nReqLevel <= 3 && GetHasSpell(SPELL_SEARING_LIGHT, oGuide)) return SPELL_SEARING_LIGHT;
    if (nReqLevel <= 3 && GetHasSpell(SPELL_PRAYER, oGuide)) return SPELL_PRAYER;
    if (nReqLevel <= 4 && GetHasSpell(SPELL_DIVINE_POWER, oGuide)) return SPELL_DIVINE_POWER;
    if (nReqLevel <= 4 && GetHasSpell(SPELL_DEATH_WARD, oGuide)) return SPELL_DEATH_WARD;
    if (nReqLevel <= 6 && GetHasSpell(SPELL_BLADE_BARRIER, oGuide)) return SPELL_BLADE_BARRIER;
    if (nReqLevel <= 7 && GetHasSpell(SPELL_REGENERATE, oGuide)) return SPELL_REGENERATE;
    if (nReqLevel <= 8 && GetHasSpell(SPELL_MASS_HEAL, oGuide)) return SPELL_MASS_HEAL;
    if (nReqLevel <= 9 && GetHasSpell(SPELL_IMPLOSION, oGuide)) return SPELL_IMPLOSION;
    return -1;
}

int MW_Pool_Campbell(object oGuide, int nReqLevel, int bHealPass)
{
    if (bHealPass)
    {
        if (nReqLevel <= 1 && GetHasSpell(SPELL_CURE_LIGHT_WOUNDS, oGuide)) return SPELL_CURE_LIGHT_WOUNDS;
        if (nReqLevel <= 2 && GetHasSpell(SPELL_CURE_MODERATE_WOUNDS, oGuide)) return SPELL_CURE_MODERATE_WOUNDS;
        if (nReqLevel <= 3 && GetHasSpell(SPELL_CURE_SERIOUS_WOUNDS, oGuide)) return SPELL_CURE_SERIOUS_WOUNDS;
        if (nReqLevel <= 4 && GetHasSpell(SPELL_CURE_CRITICAL_WOUNDS, oGuide)) return SPELL_CURE_CRITICAL_WOUNDS;
        return -1;
    }
    if (nReqLevel <= 3 && GetHasSpell(SPELL_HASTE, oGuide)) return SPELL_HASTE;
    if (nReqLevel <= 4 && GetHasSpell(SPELL_DOMINATE_PERSON, oGuide)) return SPELL_DOMINATE_PERSON;
    if (nReqLevel <= 6 && GetHasSpell(SPELL_DIRGE, oGuide)) return SPELL_DIRGE;
    return -1;
}

int MW_Pool_McKenna(object oGuide, int nReqLevel, int bHealPass)
{
    if (bHealPass)
    {
        if (nReqLevel <= 5 && GetHasSpell(SPELL_CURE_CRITICAL_WOUNDS, oGuide)) return SPELL_CURE_CRITICAL_WOUNDS;
        if (nReqLevel <= 7 && GetHasSpell(SPELL_HEAL, oGuide)) return SPELL_HEAL;
        return -1;
    }
    if (nReqLevel <= 1 && GetHasSpell(SPELL_ENTANGLE, oGuide)) return SPELL_ENTANGLE;
    if (nReqLevel <= 2 && GetHasSpell(SPELL_BARKSKIN, oGuide)) return SPELL_BARKSKIN;
    if (nReqLevel <= 4 && GetHasSpell(SPELL_ICE_STORM, oGuide)) return SPELL_ICE_STORM;
    if (nReqLevel <= 7 && GetHasSpell(SPELL_FIRE_STORM, oGuide)) return SPELL_FIRE_STORM;
    if (nReqLevel <= 7 && GetHasSpell(SPELL_CREEPING_DOOM, oGuide)) return SPELL_CREEPING_DOOM;
    if (nReqLevel <= 8 && GetHasSpell(SPELL_STORM_OF_VENGEANCE, oGuide)) return SPELL_STORM_OF_VENGEANCE;
    if (nReqLevel <= 9 && GetHasSpell(SPELL_ELEMENTAL_SWARM, oGuide)) return SPELL_ELEMENTAL_SWARM;
    return -1;
}

int MW_Pool_Aurelius(object oGuide, int nReqLevel, int bHealPass)
{
    if (bHealPass)
    {
        if (nReqLevel <= 1 && GetHasSpell(SPELL_CURE_LIGHT_WOUNDS, oGuide)) return SPELL_CURE_LIGHT_WOUNDS;
        if (nReqLevel <= 4 && GetHasSpell(SPELL_CURE_SERIOUS_WOUNDS, oGuide)) return SPELL_CURE_SERIOUS_WOUNDS;
        if (nReqLevel <= 4 && GetHasSpell(SPELL_CURE_CRITICAL_WOUNDS, oGuide)) return SPELL_CURE_CRITICAL_WOUNDS;
        return -1;
    }
    if (nReqLevel <= 1 && GetHasSpell(SPELL_DIVINE_FAVOR, oGuide)) return SPELL_DIVINE_FAVOR;
    if (nReqLevel <= 1 && GetHasSpell(SPELL_BLESS, oGuide)) return SPELL_BLESS;
    if (nReqLevel <= 2 && GetHasSpell(SPELL_AID, oGuide)) return SPELL_AID;
    if (nReqLevel <= 3 && GetHasSpell(SPELL_SEARING_LIGHT, oGuide)) return SPELL_SEARING_LIGHT;
    if (nReqLevel <= 3 && GetHasSpell(SPELL_PRAYER, oGuide)) return SPELL_PRAYER;
    if (nReqLevel <= 4 && GetHasSpell(SPELL_DEATH_WARD, oGuide)) return SPELL_DEATH_WARD;
    return -1;
}

// Dispatch to the guide's own pool by tag. Extend this when adding a new
// caster guide's counterspell pool.
int MW_GuidePoolSpellAtLevel(object oGuide, int nReqLevel, int bHealPass)
{
    string sTag = GetTag(oGuide);
    if (sTag == "mw_peterson") return MW_Pool_Peterson(oGuide, nReqLevel, bHealPass);
    if (sTag == "mw_watts")    return MW_Pool_Watts(oGuide, nReqLevel, bHealPass);
    if (sTag == "mw_campbell") return MW_Pool_Campbell(oGuide, nReqLevel, bHealPass);
    if (sTag == "mw_mckenna")  return MW_Pool_McKenna(oGuide, nReqLevel, bHealPass);
    if (sTag == "mw_aurelius") return MW_Pool_Aurelius(oGuide, nReqLevel, bHealPass);
    return -1;
}

// Any countable slot left at all (any level)? Used for the out-of-slots ->
// melee switch. nReqLevel=0 makes every "nReqLevel <= X" check in the pools
// pass, so this walks the guide's entire pool.
int MW_GuideHasAnyCounterSlot(object oGuide)
{
    return MW_GuidePoolSpellAtLevel(oGuide, 0, FALSE) != -1 ||
           MW_GuidePoolSpellAtLevel(oGuide, 0, TRUE)  != -1;
}

// Spend the lowest-level qualifying slot (non-heal first, heals only as a
// last resort), announce what was sacrificed, and return the spell ID spent
// (or -1 if nothing qualified).
int MW_ConsumeCounterSlot(object oGuide, int nReqLevel)
{
    int nSpell = MW_GuidePoolSpellAtLevel(oGuide, nReqLevel, FALSE);
    if (nSpell == -1)
        nSpell = MW_GuidePoolSpellAtLevel(oGuide, nReqLevel, TRUE);
    if (nSpell == -1) return -1;

    DecrementRemainingSpellUses(oGuide, nSpell);

    object oMaster = GetMaster(oGuide);
    string sName = GetStringByStrRef(StringToInt(Get2DAString("spells", "Name", nSpell)));
    FloatingTextStringOnCreature(GetName(oGuide) + " sacrifices " + sName +
        " to fuel the counter!", oMaster, FALSE);
    return nSpell;
}

// Fall back out of Style 3 once a guide has nothing left to counter with.
void MW_SwitchToMelee(object oGuide)
{
    if (GetLocalInt(oGuide, "MW_STYLE") != 3) return; // already switched
    SetLocalInt(oGuide, "MW_STYLE", 0);
    AssignCommand(oGuide, ClearAllActions());
    object oMaster = GetMaster(oGuide);
    if (GetIsObjectValid(oMaster))
        FloatingTextStringOnCreature(GetName(oGuide) +
            " is out of spells to counter with and draws steel.", oMaster, FALSE);
}

// The actual counterspell attempt, called from the spell hook with
// OBJECT_SELF still bound to the enemy caster and oGuide the watching guide.
// Returns TRUE to let the spell continue, FALSE to abort it (silent fizzle).
int MW_CounterspellResolve(object oGuide)
{
    if (GetIsDead(oGuide) || GetLocalInt(oGuide, "MW_STYLE") != 3) return TRUE;
    if (GetDistanceBetween(oGuide, OBJECT_SELF) > 20.0) return TRUE;
    if (GetLocalInt(oGuide, MW_CTR_COOLDOWN)) return TRUE;

    int nSpellId = GetSpellId();
    int nClass   = GetLastSpellCastClass();
    int nReqLvl  = MW_GetSpellLevel(nSpellId, nClass);
    if (nReqLvl < 0) return TRUE; // can't determine level -- don't guess, don't attempt

    int nUsed = MW_ConsumeCounterSlot(oGuide, nReqLvl);
    if (nUsed == -1)
    {
        // No qualifying slot -- no attempt, no cooldown. If truly out of
        // everything, fall back to melee now.
        if (!MW_GuideHasAnyCounterSlot(oGuide)) MW_SwitchToMelee(oGuide);
        return TRUE;
    }

    // An attempt is happening: start the cooldown regardless of outcome.
    SetLocalInt(oGuide, MW_CTR_COOLDOWN, 1);
    DelayCommand(6.0, DeleteLocalInt(oGuide, MW_CTR_COOLDOWN));

    int nD20  = d20();
    int nRoll = nD20 + GetSkillRank(SKILL_SPELLCRAFT, oGuide);
    int nDC   = 15 + MW_CasterLevel(OBJECT_SELF);
    int bSuccess = (nD20 == 20) || (nD20 != 1 && nRoll >= nDC);

    object oMaster = GetMaster(oGuide);
    if (bSuccess)
    {
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_BREACH), OBJECT_SELF);
        FloatingTextStringOnCreature(
            ">> " + GetName(oGuide) + " COUNTERS it! (Spellcraft " +
            IntToString(nRoll) + " vs DC " + IntToString(nDC) + ")", oMaster, FALSE);
    }
    else
    {
        FloatingTextStringOnCreature(
            ">> " + GetName(oGuide) + " fails to counter! (rolled " +
            IntToString(nRoll) + ")", oMaster, FALSE);
    }

    if (!MW_GuideHasAnyCounterSlot(oGuide)) MW_SwitchToMelee(oGuide);

    return !bSuccess; // FALSE aborts the spell's mechanical effect on success
}

// Entry point called from X2PreSpellCastCode() (see x2_inc_spellhook.nss).
// OBJECT_SELF is the caster. Near-zero cost when nobody is watching this
// caster (the common case for every other spell cast in the module).
int MW_CounterspellHook()
{
    object oWatcher = GetLocalObject(OBJECT_SELF, MW_CTR_WATCHER);
    if (!GetIsObjectValid(oWatcher)) return TRUE;
    return MW_CounterspellResolve(oWatcher);
}
