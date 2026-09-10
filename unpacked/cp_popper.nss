// cp_popper -- Crash Party: Party Popper. Wave 0, the "everyone has something to
// do in minute one" item.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
// Pure noise and sparkle: a burst of VFX and a bang, visible and audible to
// everyone in the area. Touches nothing, harms nothing.
//
// No CP_IsOn() check -- see cp_inc.nss.

#include "cp_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (CP_Spam(oPC, "cp_pop_cd", 2.0)) return;

    object oItem = CP_FindItem(oPC, "cp_popper");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(1),
            "You reach for another popper and find only a scrap of coloured paper."))
        return;

    location lHere = GetLocation(oPC);

    int nRoll = Random(4);
    int nVfx = VFX_FNF_FIREBALL;
    switch (nRoll)
    {
        case 0: nVfx = VFX_IMP_PULSE_HOLY;   break;
        case 1: nVfx = VFX_IMP_HEAD_SONIC;   break;
        case 2: nVfx = VFX_IMP_MAGBLUE;      break;
        case 3: nVfx = VFX_IMP_HEALING_G;    break;
    }

    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(nVfx), oPC);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_COM_HIT_SONIC), lHere);
    AssignCommand(oPC, PlaySound("as_cv_bell1"));
    AssignCommand(oPC, ActionPlayAnimation(ANIMATION_FIREFORGET_VICTORY3, 1.0));

    FloatingTextStringOnCreature(GetName(oPC) + " pops a party popper!", oPC, TRUE);
}
