// q_arc_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the shaft. Stage 2 -> 3 (final, never resets), journal
// End, Bracers of the Grey Fletching + XP; the shaft is consumed (plot
// flag cleared first -- plot items resist DestroyObject). Hardened: only
// fires from stage 2 with the shaft in hand, so the reward cannot be
// re-earned by re-running the dialogue. (roadmap: arcane-archer-quest)
#include "q_arc_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QARC_GetStage(oPC) != QARC_STAGE_SHAFT) return;

    object oShaft = GetItemPossessedBy(oPC, QARC_SHAFT_TAG);
    if (!GetIsObjectValid(oShaft)) return;

    SetPlotFlag(oShaft, FALSE);
    DestroyObject(oShaft);

    QARC_SetStage(oPC, QARC_STAGE_DONE);
    AddJournalQuestEntry(QARC_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QARC_XP);
    CreateItemOnObject(QARC_BRACER_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QARC_BRACER_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Bracers of the Grey Fletching lie at your feet.");
}
