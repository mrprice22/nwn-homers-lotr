// q_bkg_finish -- fires on Halmir's induction line (prsg_conv), reached by
// handing over the black brand. Stage 2 -> 3 (final, never resets), journal
// End, Sigil of the Fallen + XP; the brand is consumed (plot flag cleared
// first -- plot items resist DestroyObject). Hardened: only fires from
// stage 2 with the brand in hand, so the reward cannot be re-earned by
// re-running the dialogue. (roadmap: blackguard-quest)
#include "q_bkg_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QBKG_GetStage(oPC) != QBKG_STAGE_BRAND) return;

    object oBrand = GetItemPossessedBy(oPC, QBKG_BRAND_TAG);
    if (!GetIsObjectValid(oBrand)) return;

    SetPlotFlag(oBrand, FALSE);
    DestroyObject(oBrand);

    QBKG_SetStage(oPC, QBKG_STAGE_DONE);
    AddJournalQuestEntry(QBKG_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QBKG_XP);
    CreateItemOnObject(QBKG_SIGIL_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QBKG_SIGIL_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Sigil of the Fallen lies at your "
            + "feet.");
}
