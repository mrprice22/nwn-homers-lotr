// q_shf_pool -- the Shifters' still pool (roadmap: shifter-quest).
// OnUsed of the pool at Beorn's steading (beorn.git.json, existing
// placed instance 36 reused -- the zep_pool003 pool, retagged
// ShfBeornPool and made usable/dynamic/plot; it had no scripts, so
// there is nothing to chain, and no script referenced the generic old
// tag "ZEP_POOL003"). Runs the second-skin trial for a PC on it:
//
//   * The form-lock fail condition: look into the pool in your true
//     form (QSHF_IsShifted FALSE -- no EFFECT_TYPE_POLYMORPH on the PC;
//     the module's proven detection idiom from dmfi_dmw_inc.nss), and
//     the attempt fails with a flavor message; nothing is granted.
//     Retry allowed -- take a wild shape and look again.
//     Deterministic: the borrowed shape is the test, no dice.
//   * Another skin at stage 1: gives the tuft, stage 1 -> 2 + journal 2.
//     At stage 2 with the tuft lost, re-gives it (never duplicates --
//     GetItemPossessedBy guard; the item is plot + cursed and only the
//     finish consumes it).
//
// Does nothing for PCs not on the trial -- to everyone else it is just
// the pool Beorn's cattle drink from.
#include "q_shf_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QSHF_GetStage(oPC);
    if (nStage < QSHF_STAGE_ACCEPTED || nStage > QSHF_STAGE_TUFT) return;
    if (QSHF_HasTuft(oPC)) return;

    // The fail condition: the face you were born with. The pool shows
    // a true form nothing but itself.
    if (!QSHF_IsShifted(oPC))
    {
        FloatingTextStringOnCreature(
            "You lean over the still water, and the pool shows you only "
            + "the face you were born with -- and gives up nothing to it. "
            + "The skin-changers' trial is taken in another shape. Come "
            + "wearing another skin, and look again.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QSHF_TUFT_RES, oPC, 1);

    if (nStage == QSHF_STAGE_ACCEPTED)
    {
        QSHF_SetStage(oPC, QSHF_STAGE_TUFT);
        AddJournalQuestEntry(QSHF_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "The trial is kept: a borrowed face looks back from the water, "
        + "and beside it -- for a moment -- another watcher, old and vast "
        + "and patient. From the reeds at the pool's rim the water lets "
        + "go a tuft of coarse dark hair, warm as though it remembered "
        + "being worn. Carry it to Halmir.",
        oPC, FALSE);
}
