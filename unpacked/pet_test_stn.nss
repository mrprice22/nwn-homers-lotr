// pet_test_stn -- OnUsed for the two dragon statues in Castle Homeless (Ground
// Floor). A test rig for the petrification timeout, asked for in roadmap item
// petrification-respawn-defect-round-3: click a statue and it turns you to stone
// at a DC nothing survives, so the 2-minute timeout and the death/respawn panel
// can be exercised on demand instead of by hunting a basilisk.
//
// WHY THIS REPLICATES DoPetrification() INSTEAD OF CALLING IT
//
// Two reasons, and both matter for the rig to be worth anything:
//
//   1. The module's copy of DoPetrification (x0_i0_spells.nss) is DEAD CODE on the
//      real path -- in-game petrification comes from base-game precompiled gaze /
//      flesh-to-stone .ncs that inline the STOCK version. A rig that called the
//      module include would be testing a code path no monster uses.
//   2. DoPetrification opens with !GetIsReactionTypeFriendly(oTarget), evaluated
//      against OBJECT_SELF. OBJECT_SELF here is a placeable, so that test is not
//      one we can reason about; the call could simply return.
//
// So this reproduces, line for line, the branch the server actually takes:
// NWN_DIFFICULTY=3 -> bShowPopup -> a PERMANENT linked EffectPetrify plus
// PopUpDeathGUIPanel(oPC, FALSE, TRUE, 40579) at 2.75s -- a death panel with the
// Respawn button disabled by the engine. That state, not a friendly approximation
// of it, is the bug being tested.
//
// The Fortitude save is REAL, at a DC no character reaches, and the immunity check
// is kept. The rig must not be able to petrify someone the real monsters could not
// -- a golem, or anyone with genuine petrification immunity, has to walk away from
// this statue exactly as they would from a medusa.

#include "x0_i0_spells"
#include "season_prof_inc"

// High enough to be automatic in practice, low enough that it is still a roll and
// still respects immunity.
const int PET_TEST_DC = 60;

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    // Same immunity gate the stock function uses.
    if (spellsIsImmuneToPetrification(oPC) == TRUE)
    {
        FloatingTextStringOnCreature("The stone dragon's gaze washes over you and finds nothing to take hold of.", oPC, FALSE);
        return;
    }

    SignalEvent(oPC, EventSpellCastAt(OBJECT_SELF, SPELL_FLESH_TO_STONE));

    if (MySavingThrow(SAVING_THROW_FORT, oPC, PET_TEST_DC, SAVING_THROW_TYPE_NONE, OBJECT_SELF))
    {
        FloatingTextStringOnCreature("You wrench your gaze away from the stone dragon's eyes.", oPC, FALSE);
        return;
    }

    // Exactly the stock link: the duration visual and the petrify, and NOTHING else.
    // A separate standalone VFX_DUR_PETRIFY would look right and then outlive the cure --
    // petrifyCheck's StripPetrify removes EFFECT_TYPE_PETRIFY, so an unlinked visual
    // would leave the player stone-skinned forever after the timeout kills them.
    effect eLink = EffectLinkEffects(EffectVisualEffect(VFX_DUR_CESSATE_NEGATIVE),
                                     EffectPetrify());

    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_DUST_EXPLOSION), oPC);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eLink, oPC);

    // The stock hardcore branch's own popup, delay and strref, verbatim: this is the
    // death window with the DISABLED Respawn button that the player reported. The
    // heartbeat watcher (bleeding.nss, petrifyCheck) is what has to dig them out of
    // it after PETRIFY_TIMEOUT.
    DelayCommand(2.75, PopUpDeathGUIPanel(oPC, FALSE, TRUE, 40579));

    AssignCommand(oPC, ClearAllActions(TRUE));

    if (SP_DEV_TOOLS)
        WriteTimestampedLogEntry("[petrify] TEST RIG petrified pc=" + GetName(oPC) +
            " statue=" + GetTag(OBJECT_SELF) + " dc=" + IntToString(PET_TEST_DC));
}
