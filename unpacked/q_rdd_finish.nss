// q_rdd_finish -- fires on Halmir's induction line (prsg_conv), reached
// by handing over the ember. Stage 2 -> 3 (final, never resets), journal
// End, Wyrmblood Amulet + XP; the ember is consumed (plot flag cleared
// first -- plot items resist DestroyObject). Hardened: only fires from
// stage 2 with the ember in hand, so the reward cannot be re-earned by
// re-running the dialogue. (roadmap: red-dragon-disciple-quest)
#include "q_rdd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QRDD_GetStage(oPC) != QRDD_STAGE_EMBER) return;

    object oEmber = GetItemPossessedBy(oPC, QRDD_EMBER_TAG);
    if (!GetIsObjectValid(oEmber)) return;

    SetPlotFlag(oEmber, FALSE);
    DestroyObject(oEmber);

    QRDD_SetStage(oPC, QRDD_STAGE_DONE);
    AddJournalQuestEntry(QRDD_QUEST, 3, oPC, FALSE, FALSE);

    GiveXPToCreature(oPC, QRDD_XP);
    CreateItemOnObject(QRDD_AMULET_RES, oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, QRDD_AMULET_TAG)))
        SendMessageToPC(oPC,
            "Your pack was full -- the Wyrmblood Amulet lies at your feet.");
}
