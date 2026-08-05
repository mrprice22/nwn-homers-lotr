#include "legfeat_inc"
#include "csp_inc"
#include "pw_inc"

void main()
{
    object oPC = GetLastPCRested();
    int iMamber = GetCampaignInt("cRegistred","iMamber",oPC);
    int nEvent = GetLastRestEventType();
    if (nEvent == REST_EVENTTYPE_REST_STARTED)
    {
        AssignCommand(oPC, ClearAllActions(TRUE));
        AssignCommand(oPC, ActionStartConversation(oPC, "emotewand", TRUE));
        return;
    }
    // REST_CANCELLED does not clear effects, so no reapplication needed there.
    // REST_FINISHED (from ForceRest) fires synchronously mid-ForceRest, before
    // ForceRest clears effects - DelayCommand ensures we run after the wipe.
    if (nEvent == REST_EVENTTYPE_REST_FINISHED && GetLocalInt(oPC, "SPFAIL_ZONE"))
        DelayCommand(0.1f, ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            EffectSpellFailure(100), oPC));

    // Concerning Pipeweed: the whole point of the strains is that the penalty
    // rides with you, so a rest must not scrub the high. The stored (strain,
    // expiry) pair is the authority; PW_Refresh re-derives the effects from it
    // and drops them only once the real hour has actually run out. Delayed for
    // the same reason as the line above - the engine's rest effect-wipe is
    // still in flight when REST_FINISHED fires. See pw_inc.nss.
    if (nEvent == REST_EVENTTYPE_REST_FINISHED)
        DelayCommand(0.5f, PW_Refresh(oPC));

    // Legendary Feats: a rest is the recovery path for a picker that was
    // dismissed, and for any level-60 character that has never seen one. This
    // fires for Force Rest too - ew_forcerest calls ForceRest, which raises
    // REST_FINISHED. Delayed for the same reason as the line above: at this
    // point ForceRest is still mid-flight and the rest menu is still closing.
    if (nEvent == REST_EVENTTYPE_REST_FINISHED
        && LegFeat_EnsureAllotment(oPC) > 0)
        DelayCommand(2.0, ExecuteScript("legfeat_open", oPC));

    // Caster spell picks: the same recovery path, for the same reason - a
    // dismissed picker, or a character that levelled past 40 before the feature
    // existed. Staggered past the legendary-feat window so a pure wizard at 60
    // that is owed both does not get them on top of each other. See csp_inc.nss.
    if (nEvent == REST_EVENTTYPE_REST_FINISHED
        && CSP_EnsureAllotment(oPC) > 0)
        DelayCommand(4.0, ExecuteScript("csp_open", oPC));
}
