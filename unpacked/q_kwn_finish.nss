// q_kwn_finish - fires on Halmir's knighthood line (prsg_conv), reached
// by reporting the planted banner. Stage 5 -> 6 (final, never resets),
// journal End, Banner of the West + XP. Hardened: only fires from stage
// 5, so the reward cannot be re-earned by re-running the dialogue.
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QKWN_GetStage(oPC) != QKWN_STAGE_PLANTED) return;

    QKWN_SetStage(oPC, QKWN_STAGE_DONE);
    AddJournalQuestEntry(QKWN_QUEST, 6, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QKWN_XP);
    CreateItemOnObject(QKWN_SHIELD_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QKWN_SHIELD_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Banner of the West lies at your feet.");
}
