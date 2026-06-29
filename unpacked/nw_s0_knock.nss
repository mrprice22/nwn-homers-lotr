//::///////////////////////////////////////////////
//:: Knock
//:: NW_S0_Knock.nss
//:://////////////////////////////////////////////
/*
    Unlocks a door or placeable.

    Module override (Homer's LOTR): the stock script refuses to unlock any
    object with the Plot flag set, and every locked object in this module is
    Plot-flagged (Plot is what stops players bashing locks open). That made
    Knock silently do nothing everywhere. This version unlocks Plot objects via
    SetLocked() -- the Plot flag still protects them from being destroyed -- but
    leaves genuinely key-required locks alone and tells the caster a key is
    needed instead of failing silently.
*/
//:://////////////////////////////////////////////
#include "x2_inc_spellhook"

void main()
{
    if (!X2PreSpellCastCode())
        return;

    object oCaster = OBJECT_SELF;
    object oTarget = GetSpellTargetObject();
    if (!GetIsObjectValid(oTarget))
        return;

    effect eVis = EffectVisualEffect(VFX_IMP_KNOCK);

    if (GetLocked(oTarget))
    {
        if (GetLockKeyRequired(oTarget) && GetLockKeyTag(oTarget) != "")
        {
            // Intentionally key-gated -- Knock cannot bypass it. Tell the caster
            // rather than failing silently.
            SendMessageToPC(oCaster,
                "This lock is held by a special mechanism -- only the right key will open it.");
        }
        else
        {
            // Unlock even Plot-flagged objects (Plot still protects vs. bashing).
            ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oTarget);
            SetLocked(oTarget, FALSE);
        }
    }
}
