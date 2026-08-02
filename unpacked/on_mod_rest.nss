#include "legfeat_inc"

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
    // ForceRest clears effects — DelayCommand ensures we run after the wipe.
    if (nEvent == REST_EVENTTYPE_REST_FINISHED && GetLocalInt(oPC, "SPFAIL_ZONE"))
        DelayCommand(0.1f, ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            EffectSpellFailure(100), oPC));

    // Legendary Feats: a rest is the recovery path for a picker that was
    // dismissed, and for any level-60 character that has never seen one. This
    // fires for Force Rest too — ew_forcerest calls ForceRest, which raises
    // REST_FINISHED. Delayed for the same reason as the line above: at this
    // point ForceRest is still mid-flight and the rest menu is still closing.
    if (nEvent == REST_EVENTTYPE_REST_FINISHED
        && LegFeat_EnsureAllotment(oPC) > 0)
        DelayCommand(2.0, ExecuteScript("legfeat_open", oPC));
}
