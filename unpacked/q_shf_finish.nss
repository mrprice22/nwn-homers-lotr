// q_shf_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the tuft. Stage 2 -> 3 (final, never resets), journal
// End, Charm of the Carrock + XP; the tuft is consumed (plot flag
// cleared first -- plot items resist DestroyObject). Hardened: only
// fires from stage 2 with the tuft in hand, so the reward cannot be
// re-earned by re-running the dialogue. (roadmap: shifter-quest)
#include "q_shf_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QSHF_GetStage(oPC) != QSHF_STAGE_TUFT) return;

    object oTuft = GetItemPossessedBy(oPC, QSHF_TUFT_TAG);
    if (!GetIsObjectValid(oTuft)) return;

    SetPlotFlag(oTuft, FALSE);
    DestroyObject(oTuft);

    QSHF_SetStage(oPC, QSHF_STAGE_DONE);
    AddJournalQuestEntry(QSHF_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QSHF_XP);
    CreateItemOnObject(QSHF_CHARM_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QSHF_CHARM_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Charm of the Carrock lies at "
            + "your feet.");
}
