// cp_fireworks -- Crash Party: the Fireworks Finale Staff. Wave 3, the spectacle.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
//
// Fires a burst of harmless VFX at the caster's feet, which has a diminishing
// chance to set off another burst, and another, up to a HARD DEPTH CAP.
//
// ## The cap is the whole point, and it is belt and braces
//
// A chain that re-triggers itself is the one shape in this whole event that can
// take the server down for real rather than for fun, and a crash mid-party costs
// the concurrency record the party exists to set. So there are three independent
// limits, and none of them relies on the probability roll coming up short:
//
//   1. CP_FW_MAX_DEPTH   -- a counter passed down the chain; it cannot recurse
//                           past 5 no matter what the dice do.
//   2. CP_FW_PER_BURST   -- how many VFX one burst may apply, fixed, not random.
//   3. the diminishing roll -- makes long chains RARE. It is the flavour, not
//                              the safety. Never make it the safety.
//
// Every effect is DURATION_TYPE_INSTANT visual only: no damage, no area effect
// object, nothing that persists, nothing that can hurt a bystander. The staff is
// a firework, not a fireball.

#include "cp_inc"

const int CP_FW_MAX_DEPTH = 5;
const int CP_FW_PER_BURST = 3;

int CP_FireworkVfx()
{
    switch (Random(6))
    {
        case 0: return VFX_FNF_FIREBALL;
        case 1: return VFX_IMP_PULSE_HOLY;
        case 2: return VFX_FNF_LOS_EVIL_20;
        case 3: return VFX_IMP_MAGBLUE;
        case 4: return VFX_FNF_SUMMON_MONSTER_3;
    }
    return VFX_IMP_HEALING_X;
}

// One burst. nDepth counts UP; the cap is checked before anything is scheduled,
// so the last permitted burst still fires but can never spawn a successor.
void CP_Burst(object oPC, location lAt, int nDepth)
{
    if (!GetIsObjectValid(oPC)) return;
    if (nDepth > CP_FW_MAX_DEPTH) return;

    int i;
    for (i = 0; i < CP_FW_PER_BURST; i++)
    {
        DelayCommand(IntToFloat(i) * 0.35,
            ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                EffectVisualEffect(CP_FireworkVfx()), lAt));
    }

    if (nDepth >= CP_FW_MAX_DEPTH) return;

    // Diminishing: 60% at depth 1, 30% at 2, 20% at 3, 15% at 4. Flavour only --
    // the depth cap above is what actually bounds this.
    if (Random(100) >= (60 / nDepth)) return;

    DelayCommand(1.2, CP_Burst(oPC, lAt, nDepth + 1));
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (CP_Spam(oPC, "cp_fw_cd", 6.0)) return;

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
