// q_pal_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the grave-dust. Stage 2 -> 3 (final, never resets),
// journal End, Talisman of the Twenty-First Tomb + XP; the dust is
// consumed (plot flag cleared first -- plot items resist DestroyObject).
// Hardened: only fires from stage 2 with the dust in hand, so the reward
// cannot be re-earned by re-running the dialogue.
// (roadmap: pale-master-quest)
#include "q_pal_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QPAL_GetStage(oPC) != QPAL_STAGE_DUST) return;

    object oDust = GetItemPossessedBy(oPC, QPAL_DUST_TAG);
    if (!GetIsObjectValid(oDust)) return;

    SetPlotFlag(oDust, FALSE);
    DestroyObject(oDust);

    QPAL_SetStage(oPC, QPAL_STAGE_DONE);
    AddJournalQuestEntry(QPAL_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QPAL_XP);
    CreateItemOnObject(QPAL_TAL_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QPAL_TAL_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Talisman of the Twenty-First Tomb lies at your feet.");
}
