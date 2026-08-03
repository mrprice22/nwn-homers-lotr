// Spider Silk Harvest (roadmap: spider-silk-harvest)
// ActionTaken on Thranduil's turn-in reply. Consumes the day's bolts, pays
// the flat bounty and closes the day. Double-guarded: no payout without the
// bolts in hand, and never twice in a day. (Dynamic silk_supply pricing is
// deferred to a v2 - see q_silk_inc.nss.)
#include "q_silk_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, QS_QUEST))
        return;
    if (QS_CountBolts(oPC) < QS_NEED)
        return;

    QS_TakeBolts(oPC, QS_NEED);
    QCD_Stamp(oPC, QS_QUEST);
    GiveGoldToCreature(oPC, QS_GOLD);
    GiveXPToCreature(oPC, QS_XP);
    AddJournalQuestEntry(QS_QUEST, 2, oPC, FALSE, FALSE, TRUE);
}
