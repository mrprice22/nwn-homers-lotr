// q_shd_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the skein. Stage 2 -> 3 (final, never resets), journal
// End, Boots of the Unlit Road + XP; the skein is consumed (plot flag
// cleared first -- plot items resist DestroyObject). Hardened: only
// fires from stage 2 with the skein in hand, so the reward cannot be
// re-earned by re-running the dialogue. (roadmap: shadowdancer-quest)
#include "q_shd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QSHD_GetStage(oPC) != QSHD_STAGE_SKEIN) return;

    object oSkein = GetItemPossessedBy(oPC, QSHD_SKEIN_TAG);
    if (!GetIsObjectValid(oSkein)) return;

    SetPlotFlag(oSkein, FALSE);
    DestroyObject(oSkein);

    QSHD_SetStage(oPC, QSHD_STAGE_DONE);
    AddJournalQuestEntry(QSHD_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QSHD_XP);
    CreateItemOnObject(QSHD_BOOTS_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QSHD_BOOTS_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Boots of the Unlit Road lie at your feet.");
}
