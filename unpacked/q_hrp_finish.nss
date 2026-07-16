// q_hrp_finish — fires on Halmir's induction line (prsg_conv), reached by
// saying the counter-word. Stage 2 -> 3 (final, never resets), journal
// End, Harper Pin + XP. Hardened: only fires from stage 2, so the reward
// cannot be re-earned by re-running the dialogue.
// (roadmap: harper-scout-quest)
#include "q_hrp_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QHRP_GetStage(oPC) != QHRP_STAGE_SOLVED) return;

    QHRP_SetStage(oPC, QHRP_STAGE_DONE);
    AddJournalQuestEntry(QHRP_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QHRP_XP);
    CreateItemOnObject(QHRP_PIN_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "HarperPin")))
        SendMessageToPC(oPC,
            "Your pack was full -- the Harper Pin lies at your feet.");
}
