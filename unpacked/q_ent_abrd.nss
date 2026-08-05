// The Thirteenth Ent (roadmap: thirteenth-ent)
// Reply action: the bard begins the two-stage concert. One attempt per
// real-world day, stamped here. Leaflock gives his first cue after a short
// pause; the bard answers it with the Bard Song feat.
#include "q_ent_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) return;

    ENT_ClearState(oPC);

    QCD_Stamp(oPC, ENT_CD_BARD);
    SetLocalInt(oPC, ENT_L_STAGE, 1);
    AddJournalQuestEntry(ENT_JOURNAL, 3, oPC);

    ENT_Tell(oPC, "Two stages, and Leaflock leads. Watch his bark: when he "
                + "stirs, use your Bard Song. He will judge both your Lore and "
                + "your Perform each time.");

    DelayCommand(ENT_CUE_DELAY, ENT_BardCue(oPC, GetLocalInt(oPC, ENT_L_SEQ)));
}
