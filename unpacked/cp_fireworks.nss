// cp_fireworks -- Crash Party: the Fireworks Finale Staff. Wave 3, the spectacle.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
//
// Fires a burst of harmless VFX around the caster, which has a diminishing
// chance to set off another burst, and another, up to a HARD DEPTH CAP.
//
// ## The shape of one burst
//
// A shell plus sparks: one big FNF effect on the spot, then a handful of small
// impact effects scattered a few metres around it, each a beat behind the last.
// Two pools rather than one is what makes it read as a firework instead of a
// stutter -- the big effects are the ones with a boom and a bloom, and firing
// four of those on top of each other is a wall of noise, while four small ones
// alone is a fizzle.
//
// ## The cap is the whole point, and it is belt and braces
//
// A chain that re-triggers itself is the one shape in this whole event that can
// take the server down for real rather than for fun, and a crash mid-party costs
// the concurrency record the party exists to set. So there are three independent
// limits, and none of them relies on the probability roll coming up short:
//
//   1. CP_FW_MAX_DEPTH   -- a counter passed down the chain; it cannot recurse
//                           past 8 no matter what the dice do. Eight bursts at
//                           CP_FW_BURST_GAP apart is ~18 seconds of show, and
//                           at most 8 * (1 + CP_FW_PER_BURST) = 40 instant VFX.
//   2. CP_FW_PER_BURST   -- how many sparks one burst may apply, fixed, not
//                           random, plus exactly one shell.
//   3. the diminishing roll -- makes long chains RARE. It is the flavour, not
//                              the safety. Never make it the safety.
//
// Every effect is DURATION_TYPE_INSTANT visual only: no damage, no area effect
// object, nothing that persists, nothing that can hurt a bystander. The staff is
// a firework, not a fireball.

#include "cp_inc"

const int   CP_FW_MAX_DEPTH  = 8;    // bursts in one chain, hard ceiling
const int   CP_FW_PER_BURST  = 4;    // sparks per burst, on top of the shell
const float CP_FW_SPARK_GAP  = 0.55; // seconds between sparks inside a burst
const float CP_FW_BURST_GAP  = 2.2;  // seconds between bursts
const float CP_FW_SPREAD     = 3.5;  // metres sparks scatter from the shell

// Hellball has a visualeffects.2da row (464) but NO nwscript.nss constant, so
// it can only be named by its number. Verified against this module's own hak
// stack -- row 464 is VFX_FNF_HELLBALL -- rather than assumed.
const int CP_VFX_FNF_HELLBALL = 464;

// The shell: one per burst, the thing people look up at.
int CP_FireworkShell()
{
    switch (Random(17))
    {
        case  0: return VFX_FNF_FIREBALL;
        case  1: return VFX_FNF_ELECTRIC_EXPLOSION;
        case  2: return VFX_FNF_MYSTICAL_EXPLOSION;
        case  3: return VFX_FNF_LOS_EVIL_20;
        case  4: return VFX_FNF_LOS_HOLY_20;
        case  5: return VFX_FNF_LOS_NORMAL_20;
        case  6: return VFX_FNF_SUMMON_MONSTER_3;
        case  7: return VFX_FNF_SUMMON_GATE;
        case  8: return VFX_FNF_METEOR_SWARM;
        case  9: return VFX_FNF_SUNBEAM;
        case 10: return VFX_FNF_SOUND_BURST;
        case 11: return VFX_FNF_STRIKE_HOLY;
        case 12: return VFX_FNF_DISPEL_GREATER;
        case 13: return CP_VFX_FNF_HELLBALL;
        case 14: return VFX_FNF_GREATER_RUIN;
        case 15: return VFX_FNF_HORRID_WILTING;
    }
    return VFX_FNF_STORM;
}

// The sparks: several per burst, scattered around the shell.
int CP_FireworkSpark()
{
    switch (Random(16))
    {
        case  0: return VFX_IMP_PULSE_HOLY;
        case  1: return VFX_IMP_PULSE_FIRE;
        case  2: return VFX_IMP_PULSE_COLD;
        case  3: return VFX_IMP_PULSE_NATURE;
        case  4: return VFX_IMP_PULSE_WIND;
        case  5: return VFX_IMP_PULSE_WATER;
        case  6: return VFX_IMP_MAGBLUE;
        case  7: return VFX_IMP_HEALING_X;
        case  8: return VFX_IMP_STARBURST_RED;
        case  9: return VFX_IMP_STARBURST_GREEN;
        case 10: return VFX_IMP_FLAME_M;
        case 11: return VFX_IMP_LIGHTNING_M;
        case 12: return VFX_IMP_SONIC;
        case 13: return VFX_IMP_DUST_EXPLOSION;
        case 14: return VFX_IMP_HEAD_ODD;
    }
    return VFX_IMP_MIRV_FLAME;
}

// A point a few metres off the shell, so a burst occupies some sky instead of
// stacking every effect on one pixel. Local rather than CP_ScatterNear, which
// lives in the DM-only include.
location CP_FireworkSpot(location lAt, float fRadius)
{
    vector v = GetPositionFromLocation(lAt);
    float fAng = IntToFloat(Random(360));
    float fDist = fRadius * IntToFloat(Random(100)) / 100.0;
    v.x += fDist * cos(fAng);
    v.y += fDist * sin(fAng);
    return Location(GetAreaFromLocation(lAt), v, IntToFloat(Random(360)));
}

// One burst. nDepth counts UP; the cap is checked before anything is scheduled,
// so the last permitted burst still fires but can never spawn a successor.
void CP_Burst(object oPC, location lAt, int nDepth)
{
    if (!GetIsObjectValid(oPC)) return;
    if (nDepth > CP_FW_MAX_DEPTH) return;

    ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
        EffectVisualEffect(CP_FireworkShell()), lAt);

    int i;
    for (i = 1; i <= CP_FW_PER_BURST; i++)
    {
        DelayCommand(IntToFloat(i) * CP_FW_SPARK_GAP,
            ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                EffectVisualEffect(CP_FireworkSpark()),
                CP_FireworkSpot(lAt, CP_FW_SPREAD)));
    }

    if (nDepth >= CP_FW_MAX_DEPTH) return;

    // Diminishing, but gently: 78% for a second burst, then 71, 64, 57, 50, 43,
    // 36 -- so a chain usually runs three or four bursts and occasionally goes
    // the distance. Flavour only. The depth cap above is what actually bounds
    // this, and it is the only thing that is allowed to.
    if (Random(100) >= (85 - nDepth * 7)) return;

    DelayCommand(CP_FW_BURST_GAP, CP_Burst(oPC, lAt, nDepth + 1));
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    // Longer than it was (6s): a chain now runs up to ~18 seconds, and a 6s
    // cooldown let one player keep three of them overlapping.
    if (CP_Spam(oPC, "cp_fw_cd", 9.0)) return;

    object oItem = CP_FindItem(oPC, "cp_fireworks");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(5),
            "The staff gutters, coughs out one last spark and splinters."))
        return;

    AssignCommand(oPC, ActionPlayAnimation(ANIMATION_FIREFORGET_VICTORY1, 1.0));
    AssignCommand(oPC, PlaySound("as_cv_bell1"));
    FloatingTextStringOnCreature(
        GetName(oPC) + " sets off a firework!", oPC, TRUE);

    CP_Burst(oPC, GetLocation(oPC), 1);
}
