// q_wpm_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the notch. Stage 2 -> 3 (final, never resets), journal
// End, Buckle of the Sworn Blade + XP; the notch is consumed (plot flag
// cleared first -- plot items resist DestroyObject). Hardened: only fires
// from stage 2 with the notch in hand, so the reward cannot be re-earned
// by re-running the dialogue. (roadmap: weapon-master-quest)
#include "q_wpm_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QWPM_GetStage(oPC) != QWPM_STAGE_NOTCH) return;

    object oNotch = GetItemPossessedBy(oPC, QWPM_NOTCH_TAG);
    if (!GetIsObjectValid(oNotch)) return;

    SetPlotFlag(oNotch, FALSE);
    DestroyObject(oNotch);

    QWPM_SetStage(oPC, QWPM_STAGE_DONE);
    AddJournalQuestEntry(QWPM_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QWPM_XP);
    CreateItemOnObject(QWPM_BELT_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QWPM_BELT_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Buckle of the Sworn Blade lies at "
            + "your feet.");
}
