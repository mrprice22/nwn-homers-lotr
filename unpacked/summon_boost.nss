//::///////////////////////////////////////////////
//:: Summon / Companion power scaling
//:: summon_boost
//:://////////////////////////////////////////////
/*
    Scales a druid's/ranger's summoned creatures and animal companions with the
    master's investment: class level, Animal Empathy skill, and the existing
    Conjuration spell-focus feat line (Focus -> Greater -> Epic Spell Focus).

    Boosts HP (via ability scores), saving throws, attack bonus and AC so
    late-game pets stay relevant on this high-magic server.

    Called once, at spawn, from the associate OnSpawn scripts nw_ch_ac9 /
    ww_ch_ac9 / nw_ch_summon_9 (added alongside the existing bst_install hook).

    OnSpawn timing note: at the instant OnSpawn fires, GetMaster() and the
    associate wiring are often not populated yet. We classify OBJECT_SELF with
    GetAssociateType() (no dependence on the master's associate list) and, if the
    link isn't ready, re-run ourselves via a short DelayCommand until it resolves.

    High-magic tuning -- the caps are the single knob to dial the system up or
    down. Only stock feats/skills are read; no new feat is introduced.
*/
//:://////////////////////////////////////////////

const int SB_MAX_TRIES = 6; // ~3s of 0.5s retries while the master link settles

int clampMax(int n, int nMax) { return (n > nMax) ? nMax : n; }

void main()
{
    object oSelf = OBJECT_SELF;

    // Apply once per creature.
    if (GetLocalInt(oSelf, "summon_boosted")) return;

    object oMaster = GetMaster(oSelf);
    int    nType   = GetAssociateType(oSelf);

    // Not wired up yet (master link / association not populated at OnSpawn)?
    // Retry shortly rather than silently giving up.
    if (!GetIsObjectValid(oMaster) || nType == ASSOCIATE_TYPE_NONE)
    {
        int nTries = GetLocalInt(oSelf, "summon_boost_try");
        if (nTries < SB_MAX_TRIES)
        {
            SetLocalInt(oSelf, "summon_boost_try", nTries + 1);
            DelayCommand(0.5, ExecuteScript("summon_boost", oSelf));
        }
        return;
    }

    // Only boost the master's own summoned creatures and animal companions.
    // (Familiars, dominated and henchmen are intentionally excluded -- and, being
    // a resolved type, they fall out here with no further retries.)
    if (nType != ASSOCIATE_TYPE_SUMMONED && nType != ASSOCIATE_TYPE_ANIMALCOMPANION)
        return;

    SetLocalInt(oSelf, "summon_boosted", 1);

    // ---- Read the master's inputs ------------------------------------------
    int nDruid  = GetLevelByClass(CLASS_TYPE_DRUID,  oMaster);
    int nRanger = GetLevelByClass(CLASS_TYPE_RANGER, oMaster);

    // Driving class level: druid drives summons; an animal companion may be a
    // ranger's, so companions take the greater of the two.
    int bCompanion = (nType == ASSOCIATE_TYPE_ANIMALCOMPANION);
    int nLevel = nDruid;
    if (bCompanion && nRanger > nLevel) nLevel = nRanger;
    if (nLevel <= 0) return; // not a druid/ranger master -- leave stock stats.

    int nAE = GetSkillRank(SKILL_ANIMAL_EMPATHY, oMaster);
    if (nAE < 0) nAE = 0; // untrained cross-class returns -1

    // Conjuration focus tier held (cumulative feat line): 0..3.
    int nConj = 0;
    if (GetHasFeat(FEAT_SPELL_FOCUS_CONJURATION,         oMaster)) nConj = 1;
    if (GetHasFeat(FEAT_GREATER_SPELL_FOCUS_CONJURATION, oMaster)) nConj = 2;
    if (GetHasFeat(FEAT_EPIC_SPELL_FOCUS_CONJURATION,    oMaster)) nConj = 3;

    // ---- Compute bonuses (high-magic tuning; caps are the knob) -------------
    // Attack:  +1/2 lvl, +1/8 AE ranks, +2 per Conjuration tier      cap +20
    int nAB   = clampMax(nLevel / 2 + nAE / 8 + nConj * 2, 20);
    // AC dodge:+1/3 lvl, +1/10 AE ranks, Conj +1/+2/+4 (Focus/Gr/Ep) cap +12
    int nACc  = (nConj == 3) ? 4 : nConj;
    int nAC   = clampMax(nLevel / 3 + nAE / 10 + nACc, 12);
    // Saves:   +1/2 lvl, +1/5 AE ranks, +2 per Conjuration tier       cap +20
    int nSave = clampMax(nLevel / 2 + nAE / 5 + nConj * 2, 20);
    // Abilities (all six): +1/2 lvl, +1/4 AE ranks, +2 per tier       cap +24
    int nAbil = clampMax(nLevel / 2 + nAE / 4 + nConj * 2, 24);

    // ---- Build one linked, permanent, supernatural effect ------------------
    // Ability boosts raise HP (CON), damage/carry (STR), reflex/AC (DEX) and
    // mind-effect resistance (mentals). Supernatural => cannot be dispelled,
    // matching the module's epic-summon theme.
    effect eLink = EffectAttackIncrease(nAB);
    eLink = EffectLinkEffects(eLink, EffectSavingThrowIncrease(SAVING_THROW_ALL, nSave));
    eLink = EffectLinkEffects(eLink, EffectACIncrease(nAC, AC_DODGE_BONUS));
    if (nAbil > 0)
    {
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(ABILITY_STRENGTH,     nAbil));
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(ABILITY_DEXTERITY,    nAbil));
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(ABILITY_CONSTITUTION, nAbil));
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(ABILITY_INTELLIGENCE, nAbil));
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(ABILITY_WISDOM,       nAbil));
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(ABILITY_CHARISMA,     nAbil));
    }
    eLink = SupernaturalEffect(eLink);

    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eLink, oSelf);

    // Brief spawn-in flourish so the boost is visible.
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_SUPER_HEROISM), oSelf);

    // TEMPORARY diagnostic readout (only the pet's owner sees it). Confirms the
    // system fired and shows the applied magnitudes. Remove or gate once verified.
    SendMessageToPC(oMaster,
        "Your " + GetName(oSelf) + " is empowered: +" + IntToString(nAB) +
        " attack, +" + IntToString(nAC) + " AC, +" + IntToString(nSave) +
        " all saves, +" + IntToString(nAbil) + " all ability scores.");
}
