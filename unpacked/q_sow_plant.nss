// q_sow_plant -- OnUsed of the three Prancing Pony tables retagged
// SowDrop1..3 (existing placed instances in theprancingpo001.git.json,
// made usable for this quest). Plants one forged letter under OBJECT_SELF
// for a PC on the Sowing Discord job:
//
//   * Not carrying a letter: silent no-op -- to everyone else this is
//     just a table.
//   * Not in stealth mode (QSOW_IsUnseen -- the toggled mode, the same
//     deterministic test as the Quiet Knives dead drop): fail with a
//     retry message, nothing consumed. Step into shadow and try again.
//   * This table already holds this PC's letter (per-PC local int keyed
//     by UUID on the placeable): refused -- find a DIFFERENT table.
//   * Otherwise: one letter slides under the tabletop. On the third, the
//     plant stamp is written, the journal advances, and the Sheriff of
//     Bree is QSOW_SHERIFF_DELAY seconds away.
//
// (roadmap: sowing-discord-bree)
#include "q_sow_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    object oLetter = GetItemPossessedBy(oPC, QSOW_LETTER_TAG);
    if (!GetIsObjectValid(oLetter)) return;   // not on the job: just a table

    if (!QSOW_IsUnseen(oPC))
    {
        FloatingTextStringOnCreature(
            "Half the taproom could mark your hand sliding under that "
            + "tabletop. Ferny was clear: unseen, or not at all. Slip into "
            + "shadow, move quietly, and try the table again.",
            oPC, FALSE);
        return;
    }

    string sMark = "Q_SOW_" + GetObjectUUID(oPC);
    if (GetLocalInt(OBJECT_SELF, sMark))
    {
        FloatingTextStringOnCreature(
            "Your letter is already wedged under this table. A second one "
            + "here helps nobody -- pick a different table.",
            oPC, FALSE);
        return;
    }

    SetPlotFlag(oLetter, FALSE);   // plot items resist DestroyObject
    DestroyObject(oLetter);
    SetLocalInt(OBJECT_SELF, sMark, 1);

    int nLeft = QSOW_LettersHeld(oPC) - 1;   // the destroyed one still counts this frame
    if (nLeft > 0)
    {
        FloatingTextStringOnCreature(
            "Unseen, the forged letter slides beneath the tabletop, one "
            + "corner left showing -- enough for the wrong pair of eyes. "
            + IntToString(nLeft) + " letter"
            + (nLeft == 1 ? "" : "s") + " to go.",
            oPC, FALSE);
        return;
    }

    // Third letter placed -- the forgeries start working.
    QCD_Stamp(oPC, QSOW_PLANT);
    AddJournalQuestEntry(QSOW_QUEST, 2, oPC, FALSE, FALSE, TRUE);
    FloatingTextStringOnCreature(
        "The last forged letter settles under the tabletop. Somewhere "
        + "behind you a chair scrapes and a voice goes low and ugly. The "
        + "seed is sown -- it might be wise not to be standing here when "
        + "the law arrives.",
        oPC, FALSE);

    DelayCommand(QSOW_SHERIFF_DELAY,
        QSOW_SheriffArrives(GetLocation(OBJECT_SELF), oPC));
}
