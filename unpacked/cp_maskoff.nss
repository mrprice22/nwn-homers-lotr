// cp_maskoff -- Crash Party: puts the Mask of a Thousand Faces wearer back.
//
// Scheduled by cp_mask.nss. Split into its own script so the revert survives as a
// plain ExecuteScript rather than a captured DelayCommand closure, and so it can
// be run by hand if someone ever gets stuck.
//
// Honours the sequence counter: only the LATEST mask activation is allowed to
// revert. Without that, re-masking at 80s would be undone by the first
// activation's 90s timer ten seconds later.

#include "cp_inc"

const string CP_MASK_SEQ = "CP_MASK_SEQ";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    int nSeq = GetLocalInt(oPC, CP_MASK_SEQ);
    int nSeen = GetLocalInt(oPC, "CP_MASK_SEQ_SEEN") + 1;
    SetLocalInt(oPC, "CP_MASK_SEQ_SEEN", nSeen);
    if (nSeen < nSeq) return;   // a newer mask is still running

    DeleteLocalInt(oPC, CP_MASK_SEQ);
    DeleteLocalInt(oPC, "CP_MASK_SEQ_SEEN");

    // Hand the face back to whoever else is still borrowing one -- if the Cloak
    // is on, it keeps rerolling and this says nothing, because "your own face
    // returns" would be a visible lie. The Cloak coming off is then what puts
    // the real face back, for both items at once.
    if (CP_FaceRelease(oPC, CP_FACE_MASK))
        SendMessageToPC(oPC, "The mask loosens and your own face returns.");
}
