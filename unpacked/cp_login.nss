// cp_login -- Crash Party: per-login hygiene for anything the event leaves on a
// character that a logout would otherwise freeze in place.
//
// Two jobs, both of them about state that SURVIVES a logout while the timer
// meant to clean it up does not.
//
// Run once per login from mod_cliententer.nss.
//
// ## Why this has to exist
//
// SetCreatureAppearanceType writes Appearance_Type, which is a SAVED FIELD in the
// .bic -- and this module exports characters on client exit (mod_clientexit.nss)
// and periodically on the heartbeat (pc_export_inc.nss). The mask's revert, by
// contrast, is a DelayCommand, and every pending DelayCommand dies when the
// player logs out.
//
// So without this script: mask up, log out inside the 90 second window, and you
// come back a penguin FOREVER, with no item and no command able to change it
// back. That is a permanent, player-visible character corruption from a joke
// item, and it is exactly the kind of thing a party full of people logging in
// and out would find within the hour.
//
// The true form is stashed on the PC (a creature local, which is serialised into
// the .bic alongside the appearance), so it survives the same logout that caused
// the problem and is still there to restore from.
//
// Deliberately unconditional: no sequence guard, no CP_MODE check. If the stash
// says the player is masked at login, they are masked, and they get their face
// back.

#include "cp_inc"

const string CP_MASK_TRUE = "CP_MASK_TRUEFORM";
const string CP_MASK_SEQ  = "CP_MASK_SEQ";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // (2) Tipsiness. The counter is a creature local and so rides out a logout,
    // but the belch chain that decays it is a DelayCommand and does not. Left
    // alone, someone who logged out drunk comes back permanently at whatever
    // tipsiness they reached, and their next sip resumes at maximum. Reset it:
    // a night's sleep sobers you up.
    if (GetLocalInt(oPC, "CP_TIPSY") > 0 || GetLocalInt(oPC, "CP_TIPSY_UNTIL") > 0)
    {
        DeleteLocalInt(oPC, "CP_TIPSY");
        DeleteLocalInt(oPC, "CP_TIPSY_UNTIL");
        DeleteLocalInt(oPC, "CP_TIPSY_NEXT");
    }

    // (3) The penguin nudge throttle. CP_Spam parks a LocalInt and deletes it on
    // a DelayCommand -- and the local is saved into the .bic while the delete is
    // not. A player who logged out within ten minutes of their first visit would
    // otherwise never be nudged again. Same mismatch as the mask and the
    // tipsiness counter above; harmless here, but it costs one delete to be
    // right rather than nearly right.
    DeleteLocalInt(oPC, "cp_nudge");

    // (1) The mask.
    if (!GetLocalInt(oPC, CP_MASK_TRUE + "_SET")) return;

    int nTrue = GetLocalInt(oPC, CP_MASK_TRUE);

    // Clear the bookkeeping first, so a restore that somehow fails cannot leave
    // a stale stash that would overwrite a legitimate appearance next login.
    DeleteLocalInt(oPC, CP_MASK_TRUE);
    DeleteLocalInt(oPC, CP_MASK_TRUE + "_SET");
    DeleteLocalInt(oPC, CP_MASK_SEQ);
    DeleteLocalInt(oPC, "CP_MASK_SEQ_SEEN");

    if (GetAppearanceType(oPC) == nTrue) return;   // already fine

    SetCreatureAppearanceType(oPC, nTrue);
    SendMessageToPC(oPC,
        "The mask you fell asleep in has been prised off. You look like yourself again.");
}
