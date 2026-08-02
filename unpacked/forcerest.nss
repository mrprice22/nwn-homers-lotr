#include "pers_state_inc"
#include "legfeat_inc"

void main()
{
    object oPC = GetPCSpeaker();
    ForceRest(oPC);
    if (GetLocalInt(oPC, "SPFAIL_ZONE"))
        DelayCommand(0.2f, ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            EffectSpellFailure(100), oPC));
    DelayCommand(0.5, PersState_Snapshot(oPC));

    // Legendary Feats: this is where a rest actually completes in this module.
    // The module cancels the engine's own rest at REST_STARTED to open the rest
    // menu (hence "Resting. / Cancelled Rest." in the log), so REST_FINISHED is
    // not a path a player reaches by resting normally — ForceRest is. Hooking
    // the action script is deterministic; on_mod_rest keeps a REST_FINISHED
    // hook as a fallback, and re-opening is harmless because LegFeat_Open
    // destroys any existing window before building a new one.
    if (LegFeat_EnsureAllotment(oPC) > 0)
        DelayCommand(2.0, ExecuteScript("legfeat_open", oPC));
}
