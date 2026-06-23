#include "bank_box_inc"

void main()
{
    object oPC = GetPCSpeaker();
    CommitFamilyBoxes(oPC, "dialog");
    ExportSingleCharacter(oPC);
}
