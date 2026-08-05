// The Thirteenth Ent (roadmap: thirteenth-ent)
// Reply action: the druid takes Leaflock's trial. One attempt per real-world
// day, stamped here so a failure costs the day just as a success does.
#include "q_ent_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) return;

    ENT_ClearState(oPC);
    ENT_BurnTruffles(oPC);

    QCD_Stamp(oPC, ENT_CD_DRUID);
    SetLocalInt(oPC, ENT_L_DRUID, 1);
    AddJournalQuestEntry(ENT_JOURNAL, 1, oPC);

    ENT_Tell(oPC, "Leaflock's riddle: a boar's nose in Fangorn's loam, then "
                + "Nature's Balance cast over his roots -- and be quick about "
                + "it, a truffle out of the earth dies fast.");
}
