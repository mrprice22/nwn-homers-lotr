// Beorn's Garden (roadmap: beorns-garden)
// ActionTaken on Grimbeorn's turn-in reply. Consumes the day's pelts, pays
// the randomized bounty from Beorn's stores and closes the day.
// Double-guarded: no payout without both legs done, and never twice a day.
// (The honey leg is consumed implicitly - the per-hive calendar keys expire
// at UTC midnight along with everything else.)
#include "q_brn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, BRN_QUEST))
        return;
    if (BRN_CountPelts(oPC) < BRN_NEED_PELTS)
        return;
    if (BRN_CountHoney(oPC) < BRN_NEED_HONEY)
        return;

    BRN_TakePelts(oPC, BRN_NEED_PELTS);
    QCD_Stamp(oPC, BRN_QUEST);

    GiveGoldToCreature(oPC, BRN_GOLD_BASE + Random(201));   // 250-450 gp
    GiveXPToCreature(oPC, BRN_XP);

    // Randomized extra from Beorn's stores: always a honeycomb, sometimes
    // a second, sometimes a potent draught alongside it.
    CreateItemOnObject("q_brn_comb", oPC, 1);
    int nRoll = d100();
    if (nRoll > 85)
        CreateItemOnObject("nw_it_mpotion003", oPC, 1);  // Cure Serious Wounds
    else if (nRoll > 60)
        CreateItemOnObject("q_brn_comb", oPC, 1);

    AddJournalQuestEntry(BRN_QUEST, 2, oPC, FALSE, FALSE, TRUE);
}
