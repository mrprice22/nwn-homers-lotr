#include "bank_box_inc"

void main()
{
    object oPC = GetExitingObject();
    CommitStrongBoxes(oPC, "area_exit");
    CommitFamilyBoxes(oPC, "area_exit");
    ExportSingleCharacter(oPC);
}
