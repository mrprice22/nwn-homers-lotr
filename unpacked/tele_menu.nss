// tele_menu - Reply action on "Teleports." : populate the dynamic teleport-menu
// tokens before the Teleports sub-menu (entry) renders.
//   5090-5094 = "Slot 1..5: <area name or Unused>"
//   5095      = last Well-of-Eru return-point area name (or "Unused")
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    int i;
    for (i = 1; i <= 5; i++)
        SetCustomToken(5089 + i, "Slot " + IntToString(i) + ": " + Tele_SlotName(oPC, i));
    SetCustomToken(5095, Tele_SlotName(oPC, 0));
}
