// q_bkg_altar -- the Blackguards' fall-rite (roadmap: blackguard-quest).
// OnUsed of the torture-rack in the Keep of Barad-Dur
// (baraddurkeep.git.json, existing placed instance 94 of plc_torture1
// reused -- retagged BkgFallAltar, made usable; it was Static with no
// scripts, so there is nothing to chain, and no code referenced the old
// tag "Torture Equipment"). Runs the Black Oath for a PC on the rite:
//
//   * The oath's condition: come to the rack bleeding (QBKG_ComesBleeding
//     -- GetCurrentHitPoints < GetMaxHitPoints, "blood freely given").
//     Come whole and the rite fails with a flavor message; nothing
//     granted, nothing shifted. Retry allowed -- take a wound and swear
//     again. Deterministic: the wound is the test, no dice.
//   * Bleeding at stage 1: THIS is the fall. The rite drives the PC's
//     alignment hard toward evil ONCE (AdjustAlignment, ALIGNMENT_EVIL,
//     bAllPartyMembers = FALSE so only the swearer falls), brands the
//     black iron token into the hand, and moves stage 1 -> 2 + journal 2.
//   * At stage 2 with the brand lost, re-gives the brand but does NOT
//     shift again (the fall already happened; never duplicates -- the item
//     is plot + cursed and only the finish consumes it).
//
// Does nothing for PCs not on the rite -- to everyone else it is just the
// Dark Tower's cold iron.
#include "q_bkg_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QBKG_GetStage(oPC);
    if (nStage < QBKG_STAGE_ACCEPTED || nStage > QBKG_STAGE_BRAND) return;
    if (QBKG_HasBrand(oPC)) return;

    // The oath takes blood freely given, or nothing.
    if (!QBKG_ComesBleeding(oPC))
    {
        FloatingTextStringOnCreature(
            "You lay a whole hand on the cold iron, and the rack gives "
            + "nothing back. The Black Oath is not sworn clean-handed -- it "
            + "takes blood freely given. Come to it bearing a fresh wound "
            + "and swear again.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QBKG_BRAND_RES, oPC, 1);

    if (nStage == QBKG_STAGE_ACCEPTED)
    {
        // The fall -- applied exactly once, on this transition only.
        AdjustAlignment(oPC, ALIGNMENT_EVIL, QBKG_FALL_SHIFT, FALSE);
        QBKG_SetStage(oPC, QBKG_STAGE_BRAND);
        AddJournalQuestEntry(QBKG_QUEST, 2, oPC, FALSE, FALSE);

        FloatingTextStringOnCreature(
            "Your blood falls on the black iron, and the iron drinks it. "
            + "Something in you turns and does not turn back -- the fall the "
            + "Black Captain's book is written to remember. A brand of cold "
            + "iron cools in your palm. Carry it to Halmir.",
            oPC, FALSE);
        return;
    }

    // Stage 2, brand was lost -- re-give it, but the fall is already spent.
    FloatingTextStringOnCreature(
        "The rack burns you another brand of cold iron -- the oath was "
        + "already sworn, and asks nothing more of you. Carry it to Halmir.",
        oPC, FALSE);
}
