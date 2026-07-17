// q_sow_pay -- fires on Ferny's payout line (ferny_convo2), reached only
// through the q_sow_c_rdy turn-in greeting. Pays 500-800 gp of
// "morgul-silver" and 500 XP; the FIRST completion ever also hands over
// the Morgul-Weave Cloak (repeat completions are gold + XP only --
// times_done lives in questcddb, read here as "no previous turn-in
// stamp"). Stamps the daily cooldown and closes the journal. Hardened:
// only fires in the ready state, so re-running the dialogue can't
// double-pay. No faction/reputation changes yet -- rep integration waits
// on the faction-scaffolding roadmap item. (roadmap: sowing-discord-bree)
#include "q_sow_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!QSOW_ReadyToTurnIn(oPC)) return;

    int bFirst = (QCD_LastStamp(oPC, QSOW_QUEST) == 0);

    QCD_Stamp(oPC, QSOW_QUEST);
    AddJournalQuestEntry(QSOW_QUEST, 3, oPC, FALSE, FALSE, TRUE);

    GiveGoldToCreature(oPC, QSOW_GOLD_BASE + Random(QSOW_GOLD_SPREAD + 1));
    GiveXPToCreature(oPC, QSOW_XP);

    if (bFirst)
    {
        CreateItemOnObject(QSOW_CLOAK_RES, oPC, 1);
        if (!GetIsObjectValid(GetItemPossessedBy(oPC, QSOW_CLOAK_TAG)))
            SendMessageToPC(oPC,
                "Your pack was full -- the Morgul-Weave Cloak lies at "
                + "your feet.");
    }
}
