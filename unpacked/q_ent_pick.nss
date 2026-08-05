// The Thirteenth Ent (roadmap: thirteenth-ent)
// OnUsed of a truffle of Fangorn (placeable q_ent_trufp, script-spawned at
// AP_thirteenthent_2..6). Only a boar-shaped druid on the trial can root one
// up; doing so opens the short window in which the Nature's Balance ritual
// must be finished at Leaflock's roots.
#include "q_ent_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsObjectValid(oPC)) return;

    if (!ENT_IsTruffleHunter(oPC))
    {
        ENT_Tell(oPC, "Nothing but leaf-mould and old roots. Whatever your "
                    + "nose found, your hands cannot.");
        return;
    }

    ENT_BurnTruffles(oPC);          // one fresh truffle at a time
    CreateItemOnObject(ENT_TRUFF_RES, oPC, 1);

    int nSeq = GetLocalInt(oPC, ENT_L_SEQ);
    SetLocalInt(oPC, ENT_L_TRUFFLE, 1);
    DelayCommand(ENT_TRUFF_SECS, ENT_TruffleExpire(oPC, nSeq));

    AddJournalQuestEntry(ENT_JOURNAL, 2, oPC);
    ENT_Tell(oPC, "You root up a truffle of Fangorn. Its earth-smell is already "
                + "fading -- get back to Leaflock, put off the beast-shape, and "
                + "cast Nature's Balance over his roots.");

    DestroyObject(OBJECT_SELF);
}
