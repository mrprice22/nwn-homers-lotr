// q_dvc_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the oath-light. Stage 2 -> 3 (final, never resets),
// journal End, Mantle of the Westward Vow + XP; the light is consumed
// (plot flag cleared first -- plot items resist DestroyObject). Hardened:
// only fires from stage 2 with the light in hand, so the reward cannot be
// re-earned by re-running the dialogue. (roadmap: divine-champion-quest)
#include "q_dvc_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QDVC_GetStage(oPC) != QDVC_STAGE_LIGHT) return;

    object oLight = GetItemPossessedBy(oPC, QDVC_LIGHT_TAG);
    if (!GetIsObjectValid(oLight)) return;

    SetPlotFlag(oLight, FALSE);
    DestroyObject(oLight);

    QDVC_SetStage(oPC, QDVC_STAGE_DONE);
    AddJournalQuestEntry(QDVC_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QDVC_XP);
    CreateItemOnObject(QDVC_CLOAK_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QDVC_CLOAK_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Mantle of the Westward Vow lies at "
            + "your feet.");
}
