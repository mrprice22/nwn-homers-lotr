// q_kwn_rally - rally ActionTaken on a gate guardsman (q_kwn_guard).
// Counts this post to the knight's banner-detail: stamps the design
// card's per-character command counter ("pdk_command") and the post flag,
// both persistent. The third spear completes the muster: stage 2 -> 3,
// journal entry 3. Hardened: only fires on the muster at an uncounted
// post, so re-running the dialogue can never double-count.
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

void main()
{
    object oPC  = GetPCSpeaker();
    int    nPost = GetLocalInt(OBJECT_SELF, QKWN_POST_VAR);

    if (nPost <= 0) return;
    if (QKWN_GetStage(oPC) != QKWN_STAGE_MUSTER) return;
    if (QKWN_HasPost(oPC, nPost)) return;

    QKWN_SetPost(oPC, nPost);
    int nCount = QKWN_GetCommand(oPC) + 1;
    QKWN_SetCommand(oPC, nCount);

    FloatingTextStringOnCreature("The guardsman stands to your banner ("
        + IntToString(nCount) + " of "
        + IntToString(QKWN_MUSTER) + " spears).", oPC, FALSE);

    if (nCount >= QKWN_MUSTER)
    {
        QKWN_SetStage(oPC, QKWN_STAGE_MUSTERED);
        AddJournalQuestEntry(QKWN_QUEST, 3, oPC, FALSE, FALSE);
        FloatingTextStringOnCreature(
            "Three spears answer your command. Report to the Gate Captain.",
            oPC, FALSE);
    }
}
