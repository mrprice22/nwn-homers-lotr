// cg_retype_inc - Caster Signature Gear: the Damage Retyper amulets
// (roadmap: Gear-to-boost-specific-mage-spells)
//
// Design page: docs.manual/Draft/CasterGear.html
//
// THE PROBLEM
// High-tier bosses are immune to death magic, so a caster's signature
// save-or-die spell is a wasted slot against exactly the fights it was saved
// for. The Damage Retyper amulets answer that: while the amulet is worn, the
// spell it names stops being a death effect and instead deals real damage of
// an EXISTING damage type the target is not immune to. No new damage type is
// invented, and the spell is not made stronger against anything that was
// already vulnerable to it - it is made USABLE against things that were not.
//
// HOW IT HOOKS IN
// stop_spellcheat.nss is the module override spellscript
// (SetModuleOverrideSpellscript("stop_spellcheat") in onmoduleload.nss). It
// runs on EVERY cast, immediately before the spell's own impact script, and
// calls CGR_OnOverrideSpellCast() with OBJECT_SELF = the caster. When we take
// a spell over we call SetModuleOverrideSpellScriptFinished(), which makes
// X2PreSpellCastCode() abort the original impact script - so the death version
// never runs and the retyped version is the only thing that happens.
//
// NOTE ON THE EQUIP HOOK: this module's Mod_OnPlrEqItm / Mod_OnPlrUnEqItm
// event slots in module.ifo.json are EMPTY - nothing is wired to them, so an
// "equip sets a flag" design would never fire here. Instead the wearer's
// amulet is re-read from the neck slot on every cast. That is strictly safer:
// there is no persistent flag to desync on relog, death or item swap.
//
// ANTI-STACKING (approved policy: hard per-effect cap, no stacking)
//   1. Only the NECK slot is ever read - a creature has exactly one, so at
//      most one Damage Retyper can be active at a time. Spares in the pack do
//      nothing.
//   2. Each amulet names exactly ONE spell, so two retypes can never apply to
//      the same cast.
//   3. Damage is re-derived from scratch each cast; nothing accumulates.
//   4. A hard damage cap per target per cast (CGR_CAP_*) sits on top of the
//      caster-level dice, so the effect cannot scale without limit.
//
// THE FOUR AMULETS (one per caster class)
//   cg_amu_cleric  Reliquary of the Unmaking     Implosion            -> divine
//   cg_amu_druid   Heartwood of the Blighted Grove Finger of Death    -> negative
//   cg_amu_sorc    Sorrow of the Nine            Wail of the Banshee  -> negative
//   cg_amu_wiz     Dreamshard of Dol Guldur      Weird                -> magical
//
// Each amulet is inert for a character with no levels in its class.

#include "x0_i0_spells"

// Tags - byte-for-byte identical to the .uti Tag / TemplateResRef fields.
const string CGR_TAG_CLERIC = "cg_amu_cleric";
const string CGR_TAG_DRUID  = "cg_amu_druid";
const string CGR_TAG_SORC   = "cg_amu_sorc";
const string CGR_TAG_WIZ    = "cg_amu_wiz";

// Hard caps. Caster level feeds the dice count, but never past CGR_DICE_CAP,
// and the rolled total is clamped to the per-target cap for the spell's shape.
const int CGR_DICE_CAP   = 40;   // max dice, whatever the caster level
const int CGR_CAP_AOE    = 300;  // per target, area spells
const int CGR_CAP_SINGLE = 400;  // single-target spells

// Roll the retyped damage: nCasterLvl dice of nSides, metamagic applied,
// then clamped to nCap.
int CGR_RollDamage(int nCasterLvl, int nSides, int nCap)
{
    int nDice = nCasterLvl;
    if (nDice > CGR_DICE_CAP) nDice = CGR_DICE_CAP;
    if (nDice < 1) nDice = 1;

    int nDamage;
    if (nSides == 8) nDamage = d8(nDice);
    else             nDamage = d6(nDice);

    int nMeta = GetMetaMagicFeat();
    if (nMeta == METAMAGIC_MAXIMIZE)     nDamage = nDice * nSides;
    else if (nMeta == METAMAGIC_EMPOWER) nDamage = nDamage + (nDamage / 2);

    if (nDamage > nCap) nDamage = nCap;
    return nDamage;
}

// Resolve the retyped hit on one target.
//
// The retype deliberately moves the saving throw off SAVING_THROW_TYPE_DEATH
// and onto SAVING_THROW_TYPE_SPELL. That is the entire mechanic: a
// death-immune creature auto-succeeds against a DEATH-subtype save, which is
// why these spells do nothing to bosses today. As ordinary typed damage on a
// spell save, the boss rolls like anything else - and a success halves the
// damage rather than negating the spell.
//
// Spell resistance is still checked, exactly as the original spell does.
void CGR_HitTarget(object oCaster, object oTarget, int nSpell, int nSides,
                   int nDamageType, int nCap, int nDCBonus, int nVfx,
                   float fDelay)
{
    if (!GetIsObjectValid(oTarget)) return;
    if (GetObjectType(oTarget) != OBJECT_TYPE_CREATURE) return;

    SignalEvent(oTarget, EventSpellCastAt(oCaster, nSpell));

    if (MyResistSpell(oCaster, oTarget, fDelay)) return;

    int nDamage = CGR_RollDamage(GetCasterLevel(oCaster), nSides, nCap);

    if (MySavingThrow(SAVING_THROW_FORT, oTarget, GetSpellSaveDC() + nDCBonus,
                      SAVING_THROW_TYPE_SPELL, oCaster, fDelay))
        nDamage = nDamage / 2;

    if (nDamage < 1) return;

    DelayCommand(fDelay, ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(nVfx), oTarget));
    DelayCommand(fDelay, ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectDamage(nDamage, nDamageType), oTarget));
}

// The amulet is worn by someone with no levels in its class: say so once and
// let the ordinary spell resolve untouched.
void CGR_Inert(object oCaster, string sClass)
{
    FloatingTextStringOnCreature(
        "The amulet stays cold - only a " + sClass
        + " can turn this spell aside from death.", oCaster, FALSE);
}

// Entry point. Called from stop_spellcheat.nss on every cast, so bail fast.
void CGR_OnOverrideSpellCast()
{
    int nSpell = GetSpellId();
    if (nSpell != SPELL_IMPLOSION
        && nSpell != SPELL_FINGER_OF_DEATH
        && nSpell != SPELL_WAIL_OF_THE_BANSHEE
        && nSpell != SPELL_WEIRD) return;

    object oCaster = OBJECT_SELF;
    if (!GetIsPC(oCaster) || GetIsDM(oCaster)) return;

    // Anti-stacking rule 1: the neck slot, and only the neck slot.
    object oAmulet = GetItemInSlot(INVENTORY_SLOT_NECK, oCaster);
    if (!GetIsObjectValid(oAmulet)) return;
    string sTag = GetTag(oAmulet);

    object oTarget;
    location lTarget;
    float fDelay;

    // ---------------------------------------------------------------- Cleric
    // Implosion: death -> divine, in the same MEDIUM sphere the spell uses.
    if (nSpell == SPELL_IMPLOSION)
    {
        if (sTag != CGR_TAG_CLERIC) return;
        if (GetLevelByClass(CLASS_TYPE_CLERIC, oCaster) < 1)
        {
            CGR_Inert(oCaster, "Cleric");
            return;
        }

        lTarget = GetSpellTargetLocation();
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_IMPLOSION), lTarget);

        oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_MEDIUM, lTarget);
        while (GetIsObjectValid(oTarget))
        {
            if (oTarget != oCaster
                && spellsIsTarget(oTarget, SPELL_TARGET_STANDARDHOSTILE, oCaster))
            {
                // The base spell casts its Fortitude save at DC+3; kept.
                CGR_HitTarget(oCaster, oTarget, nSpell, 6, DAMAGE_TYPE_DIVINE,
                              CGR_CAP_AOE, 3, VFX_IMP_DIVINE_STRIKE_HOLY,
                              GetRandomDelay(0.4, 1.2));
            }
            oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_MEDIUM, lTarget);
        }

        FloatingTextStringOnCreature(
            "The Reliquary unmakes: Implosion lands as divine damage.",
            oCaster, FALSE);
        SetModuleOverrideSpellScriptFinished();
        return;
    }

    // ----------------------------------------------------------------- Druid
    // Finger of Death: death -> negative, single target.
    if (nSpell == SPELL_FINGER_OF_DEATH)
    {
        if (sTag != CGR_TAG_DRUID) return;
        if (GetLevelByClass(CLASS_TYPE_DRUID, oCaster) < 1)
        {
            CGR_Inert(oCaster, "Druid");
            return;
        }

        oTarget = GetSpellTargetObject();
        if (!GetIsObjectValid(oTarget)) return;
        if (!spellsIsTarget(oTarget, SPELL_TARGET_SELECTIVEHOSTILE, oCaster)) return;

        CGR_HitTarget(oCaster, oTarget, nSpell, 8, DAMAGE_TYPE_NEGATIVE,
                      CGR_CAP_SINGLE, 0, VFX_IMP_NEGATIVE_ENERGY, 0.0);

        FloatingTextStringOnCreature(
            "The blighted heartwood answers: Finger of Death lands as negative damage.",
            oCaster, FALSE);
        SetModuleOverrideSpellScriptFinished();
        return;
    }

    // ------------------------------------------------------------- Sorcerer
    // Wail of the Banshee: death -> negative. The base spell reaches up to
    // caster-level creatures within 10m of the target point; mirrored here as
    // a COLOSSAL (10m) sphere with the same headcount limit.
    if (nSpell == SPELL_WAIL_OF_THE_BANSHEE)
    {
        if (sTag != CGR_TAG_SORC) return;
        if (GetLevelByClass(CLASS_TYPE_SORCERER, oCaster) < 1)
        {
            CGR_Inert(oCaster, "Sorcerer");
            return;
        }

        lTarget = GetSpellTargetLocation();
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_WAIL_O_BANSHEES), lTarget);

        int nLeft = GetCasterLevel(oCaster);
        oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, lTarget);
        while (GetIsObjectValid(oTarget) && nLeft > 0)
        {
            if (oTarget != oCaster
                && spellsIsTarget(oTarget, SPELL_TARGET_SELECTIVEHOSTILE, oCaster))
            {
                CGR_HitTarget(oCaster, oTarget, nSpell, 6, DAMAGE_TYPE_NEGATIVE,
                              CGR_CAP_AOE, 0, VFX_IMP_DEATH,
                              GetRandomDelay(0.4, 1.2));
                nLeft--;
            }
            oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, lTarget);
        }

        FloatingTextStringOnCreature(
            "Sorrow of the Nine howls: the Wail lands as negative damage.",
            oCaster, FALSE);
        SetModuleOverrideSpellScriptFinished();
        return;
    }

    // --------------------------------------------------------------- Wizard
    // Weird: death (and its mind-affecting gate) -> magical damage, in the
    // same COLOSSAL sphere. Dropping the mind gate matters as much as the
    // retype - most high-tier bosses are immune to mind-affecting too.
    if (nSpell == SPELL_WEIRD)
    {
        if (sTag != CGR_TAG_WIZ) return;
        if (GetLevelByClass(CLASS_TYPE_WIZARD, oCaster) < 1)
        {
            CGR_Inert(oCaster, "Wizard");
            return;
        }

        lTarget = GetSpellTargetLocation();
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_WEIRD), lTarget);

        oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL,
                                        lTarget, TRUE);
        while (GetIsObjectValid(oTarget))
        {
            if (oTarget != oCaster
                && spellsIsTarget(oTarget, SPELL_TARGET_SELECTIVEHOSTILE, oCaster))
            {
                CGR_HitTarget(oCaster, oTarget, nSpell, 6, DAMAGE_TYPE_MAGICAL,
                              CGR_CAP_AOE, 0, VFX_IMP_MAGBLUE,
                              GetRandomDelay(0.4, 1.2));
            }
            oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL,
                                           lTarget, TRUE);
        }

        FloatingTextStringOnCreature(
            "The Dreamshard bites: Weird lands as magical damage.",
            oCaster, FALSE);
        SetModuleOverrideSpellScriptFinished();
        return;
    }
}
