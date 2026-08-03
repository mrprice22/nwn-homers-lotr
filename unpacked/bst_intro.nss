// bst_intro - refresh the bestiary index page's boss-progress line (token 5029).
// Runs both as a dialog action (the [Back to the index] reply, where the PC is
// GetPCSpeaker) and via ExecuteScript from dmfi_activate when the book is first
// used (where the PC is OBJECT_SELF). Must run BEFORE the index entry is spoken.
#include "bst_db"
void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;
    Bst_BuildIntro(oPC);
}
