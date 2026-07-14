// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// Tag-based item script for the Frogmorton Pint (item tag = q_frog_pint,
// blueprint frogpint.uti). Single-use Unique Power Self Only, so the engine
// consumes the pint on drinking. Heals 4 hp and plays a brief, purely
// cosmetic tipsy bit -- no stats touched, nothing griefable.
#include "x2_inc_switches"

void main()
{
    if (GetUserDefinedItemEventNumber() != X2_ITEM_EVENT_ACTIVATE)
        return;

    object oPC = GetItemActivator();
    if (!GetIsObjectValid(oPC))
        return;

    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(4), oPC);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_HEALING_S), oPC);

    FloatingTextStringOnCreature("*glug* ...that's the Floating Log, all right.", oPC, FALSE);
    AssignCommand(oPC, ActionPlayAnimation(ANIMATION_LOOPING_PAUSE_DRUNK, 1.0, 4.0));
    DelayCommand(2.5, FloatingTextStringOnCreature("*hic*", oPC, FALSE));
    DelayCommand(4.0, AssignCommand(oPC, PlayVoiceChat(VOICE_CHAT_LAUGH)));

    // Stop dmfi_activate from running its generic handling afterwards.
    SetExecutedScriptReturnValue(X2_EXECUTE_SCRIPT_END);
}
