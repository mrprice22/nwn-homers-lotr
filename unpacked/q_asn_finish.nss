// q_asn_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the sealed writ. Stage 2 -> 3 (final, never resets),
// journal End, Gloves of the Quiet Hand + XP; the writ is consumed (plot
// flag cleared first -- plot items resist DestroyObject). Hardened: only
// fires from stage 2 with the writ in hand, so the reward cannot be
// re-earned by re-running the dialogue. (roadmap: assassin-quest)
#include "q_asn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QASN_GetStage(oPC) != QASN_STAGE_WRIT) return;

    object oWrit = GetItemPossessedBy(oPC, QASN_WRIT_TAG);
    if (!GetIsObjectValid(oWrit)) return;

    SetPlotFlag(oWrit, FALSE);
    DestroyObject(oWrit);

    QASN_SetStage(oPC, QASN_STAGE_DONE);
    AddJournalQuestEntry(QASN_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QASN_XP);
    CreateItemOnObject(QASN_GLOVES_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QASN_GLOVES_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Gloves of the Quiet Hand lie at "
            + "your feet.");
}
