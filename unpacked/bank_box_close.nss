// bank_box_close.nss - "I am done with my vault" / "Yes." (close strongboxes)
//
// Delegates to the shared commit helper so the personal strongbox path gets the
// same treatment as the family path: the box that is actually possessed is the
// one stored (the old code re-resolved it with a module-wide GetObjectByTag,
// which could grab the wrong same-tagged copy), duplicate boxes left behind by
// the pre-fix open path are drained, and every commit writes a bankaudit row.

#include "bank_box_inc"

void main()
{
    object oPC = GetPCSpeaker();
    CommitStrongBoxes(oPC, "dialog");
    ExportSingleCharacter(oPC);
}
