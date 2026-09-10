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

const string CP_MASK_TRUE = "CP_MASK_TRUEFORM";
const string CP_MASK_SEQ  = "CP_MASK_SEQ";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    int nSeq = GetLocalInt(oPC, CP_MASK_SEQ);
    int nSeen = GetLocalInt(oPC, "CP_MASK_SEQ_SEEN") + 1;
    SetLocalInt(oPC, "CP_MASK_SEQ_SEEN", nSeen);
    if (nSeen < nSeq) return;   // a newer mask is still running

    if (!GetLocalInt(oPC, CP_MASK_TRUE + "_SET")) return;

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_POLYMORPH), oPC);
    SetCreatureAppearanceType(oPC, GetLocalInt(oPC, CP_MASK_TRUE));
    SendMessageToPC(oPC, "The mask loosens and your own face returns.");

    DeleteLocalInt(oPC, CP_MASK_TRUE);
    DeleteLocalInt(oPC, CP_MASK_TRUE + "_SET");
    DeleteLocalInt(oPC, CP_MASK_SEQ);
    DeleteLocalInt(oPC, "CP_MASK_SEQ_SEEN");
}
