// fat_inc — soul-fatigue on the Heal spell and Heal potions
// (roadmap: heal-soul-fatigue).
//
// Design spec: docs.manual/boss-updates.html#fatigue.
//
// Turns reflexive full-heal spam into a timed resource. When a living PC is
// healed by the Heal spell (SPELL_HEAL, including potion/item activations —
// they fire the same spell id through the module override spellscript) or by
// Mass Heal, three things happen in strict order:
//   1. the heal fully resolves first (we only schedule work AFTER the real
//      impact script has run),
//   2. the PC then takes 10% of max HP as damage PER stack that was already
//      active BEFORE this heal — applied after the top-off so the heal can't
//      erase it. This can kill: at 10 prior stacks the hit is 100% of max HP.
//   3. a new stack is added.
// Each stack decays on its own independent 3-minute timer. A heal from zero
// stacks is therefore completely free: full heal, 1 stack, no damage.
//
// Hook: stop_spellcheat.nss (the SetModuleOverrideSpellscript script installed
// by onmoduleload.nss, the real Mod_OnModLoad) calls FAT_OnOverrideSpellCast()
// on every cast (via x2_inc_spellhook's X2RunUserDefinedSpellScript). The
// override script runs at spell impact, immediately BEFORE the spell's own
// impact script; our DelayCommand therefore lands after the heal has resolved.
//
// Scope / defensive rules:
//   * PCs only, never DMs. NPCs healing themselves are unaffected.
//   * An undead target isn't being healed by these spells (they harm it) —
//     no stack, no damage.
//   * Mass Heal mirrors the module impact script nw_s0_masheal.nss exactly:
//     friendly, non-undead targets in a MEDIUM sphere at the target location
//     (that script staggers its heals by a random <=~1.1 s delay per target,
//     so the fatigue hit waits FAT_LAND_MASS seconds).
//   * All delayed work is assigned to the module object so it survives the
//     caster dying/logging out; every callback re-validates its PC first.
//   * Stacks live in a local int on the PC (precedent: the brief). They are
//     wiped by a relog — accepted for now; persist via SQLite later if the
//     admin wants relogging closed off as an out.
//
// Locals used (on the PC):
//   int fat_stacks   currently active soul-fatigue stacks

const string FAT_VAR        = "fat_stacks";
const int    FAT_PCT        = 10;     // % of max HP damage per prior stack
const float  FAT_DECAY      = 180.0;  // seconds a stack lasts (3 minutes)
const float  FAT_LAND       = 1.0;    // Heal: delay so the heal resolves first
const float  FAT_LAND_MASS  = 2.0;    // Mass Heal: outlasts its staggered heals

// One stack falls off (each stack has its own independent timer).
void FAT_Decay(object oPC)
{
    if (!GetIsObjectValid(oPC)) return;
    int nStacks = GetLocalInt(oPC, FAT_VAR);
    if (nStacks <= 0) return;
    nStacks--;
    SetLocalInt(oPC, FAT_VAR, nStacks);
    if (nStacks > 0)
        FloatingTextStringOnCreature("A stack of soul-fatigue fades ("
            + IntToString(nStacks) + " remaining).", oPC, FALSE);
    else
        FloatingTextStringOnCreature(
            "The soul-fatigue lifts. The next heal is free.", oPC, FALSE);
}

// The ordered mechanic. Runs AFTER the heal has landed on oPC:
// damage for the stacks held before this heal, then add the new stack.
void FAT_ApplyToPC(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (GetIsDead(oPC)) return;   // died between cast and impact: no stack

    int nPrior = GetLocalInt(oPC, FAT_VAR);

    if (nPrior > 0)
    {
        int nDmg = GetMaxHitPoints(oPC) * FAT_PCT * nPrior / 100;
        if (nDmg > 0)
        {
            // Remove the HP directly rather than via EffectDamage. This is the
            // crux of the fix: EVERY EffectDamage damage type — including
            // DAMAGE_TYPE_MAGICAL — can be soaked by damage resistance,
            // immunity %, or DR, and geared PCs reduced the old magical hit to
            // zero. A soul-fatigue hit is a scripted cost, not an attack, so we
            // subtract HP straight off the creature: nothing can resist or be
            // immune to it.
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectVisualEffect(VFX_IMP_NEGATIVE_ENERGY), oPC);

            int nCur = GetCurrentHitPoints(oPC);
            int nNew = nCur - nDmg;
            if (nNew < 1)
            {
                // Lethal. Base-game SetCurrentHitPoints floors at 1 and never
                // kills, so force death explicitly. (A PC with outright death
                // immunity would survive at 1 HP — a rare, accepted corner.)
                SetCurrentHitPoints(oPC, 1);
                ApplyEffectToObject(DURATION_TYPE_INSTANT,
                    EffectDeath(FALSE, FALSE), oPC);
            }
            else
            {
                SetCurrentHitPoints(oPC, nNew);
            }
            FloatingTextStringOnCreature("Soul-fatigue tears at you for "
                + IntToString(nDmg) + " damage ("
                + IntToString(nPrior) + " stack" + (nPrior == 1 ? "" : "s")
                + " x " + IntToString(FAT_PCT) + "% of max HP).", oPC, FALSE);
        }
    }

    // The new stack — even if the fatigue damage just killed them.
    int nNow = GetLocalInt(oPC, FAT_VAR) + 1;
    SetLocalInt(oPC, FAT_VAR, nNow);
    AssignCommand(GetModule(), DelayCommand(FAT_DECAY, FAT_Decay(oPC)));

    FloatingTextStringOnCreature("Soul-fatigue: " + IntToString(nNow)
        + " stack" + (nNow == 1 ? "" : "s")
        + ". Another heal within 3 minutes will cost "
        + IntToString(nNow * FAT_PCT) + "% of your max HP after it lands.",
        oPC, FALSE);
}

// Entry point, called from stop_spellcheat.nss with OBJECT_SELF = the caster
// (for potions/items: the user). Runs on EVERY cast — bail out fast.
void FAT_OnOverrideSpellCast()
{
    int nSpell = GetSpellId();
    if (nSpell != SPELL_HEAL && nSpell != SPELL_MASS_HEAL) return;

    if (nSpell == SPELL_HEAL)
    {
        object oTarget = GetSpellTargetObject();
        if (!GetIsObjectValid(oTarget)) return;
        if (!GetIsPC(oTarget) || GetIsDM(oTarget)) return;
        // Heal cast at undead is an attack, not a heal — no fatigue.
        if (GetRacialType(oTarget) == RACIAL_TYPE_UNDEAD) return;
        AssignCommand(GetModule(),
            DelayCommand(FAT_LAND, FAT_ApplyToPC(oTarget)));
        return;
    }

    // Mass Heal: mirror nw_s0_masheal targeting (friendly, non-undead,
    // MEDIUM sphere at the target location).
    location lLoc = GetSpellTargetLocation();
    object oT = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_MEDIUM, lLoc);
    while (GetIsObjectValid(oT))
    {
        if (GetIsPC(oT) && !GetIsDM(oT)
            && GetRacialType(oT) != RACIAL_TYPE_UNDEAD
            && GetIsFriend(oT))
        {
            AssignCommand(GetModule(),
                DelayCommand(FAT_LAND_MASS, FAT_ApplyToPC(oT)));
        }
        oT = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_MEDIUM, lLoc);
    }
}
