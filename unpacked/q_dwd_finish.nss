// q_dwd_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the shard. Stage 2 -> 3 (final, never resets), journal
// End, Warhelm of Durin's Watch + XP; the shard is consumed (plot flag
// cleared first -- plot items resist DestroyObject). Hardened: only
// fires from stage 2 with the shard in hand, so the reward cannot be
// re-earned by re-running the dialogue. (roadmap: dwarven-defender-quest)
#include "q_dwd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QDWD_GetStage(oPC) != QDWD_STAGE_SHARD) return;

    object oShard = GetItemPossessedBy(oPC, QDWD_SHARD_TAG);
    if (!GetIsObjectValid(oShard)) return;

    SetPlotFlag(oShard, FALSE);
    DestroyObject(oShard);

    QDWD_SetStage(oPC, QDWD_STAGE_DONE);
    AddJournalQuestEntry(QDWD_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QDWD_XP);
    CreateItemOnObject(QDWD_HELM_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QDWD_HELM_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Warhelm of Durin's Watch lies at "
            + "your feet.");
}
