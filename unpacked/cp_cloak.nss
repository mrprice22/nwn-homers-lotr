// cp_cloak -- Crash Party: Cloak of a Thousand Faces. Wave 2. WORN item.
//
// Dispatched by cp_equip.nss / cp_unequip.nss; OBJECT_SELF is the wearer.
//
// While worn it rerolls your appearance every half minute or so. Cosmetic only:
// SetCreatureAppearanceType changes the model and not one stat, and it is not
// EffectPolymorph -- so it cannot interact with the module's shapeshift
// item-merge machinery (shape_merge_inc.nss) and cannot be used to launder gear
// through a form change.
//
// ## It shares the Mask's true-form stash on purpose
//
// Both items change the same field, so they must agree on what "your real face"
// is or one will restore the other's borrowed one. The stash is written once, by
// whichever item got there first, and REFERENCE COUNTED (CP_FaceClaim /
// CP_FaceRelease in cp_inc.nss): the real face goes back when the last holder
// lets go, never before.
//
// That counting is not decoration. Before it existed, using the Mask while the
// Cloak was on meant the Mask's 90s revert deleted the shared stash -- and then
// taking the Cloak off restored nothing, leaving the player as whatever the last
// reroll made them with no item and no timer that could ever put it right.
//
// cp_login.nss restores unconditionally at login, which is what stops a player
// who logged out mid-swap from being stuck as a penguin forever: Appearance_Type
// is a SAVED .bic field while every timer that would undo it dies at logout, and
// that asymmetry is the whole reason cp_login exists.

#include "cp_inc"

const string CP_CLOAK_ON   = "CP_CLOAK_ON";
const string CP_CLOAK_NEXT = "CP_CLOAK_NEXT";

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // --- taken off: put the wearer's own face back -----------------------
    if (!GetLocalInt(oPC, "cp_worn_on"))
    {
        if (!GetLocalInt(oPC, CP_CLOAK_ON)) return;
        DeleteLocalInt(oPC, CP_CLOAK_ON);
        DeleteLocalInt(oPC, CP_CLOAK_NEXT);

        // Release rather than restore: if a Mask is still counting down, IT is
        // holding the real face and the player stays masked until it expires.
        // Either way the message only claims what actually happened.
        if (CP_FaceRelease(oPC, CP_FACE_CLOAK))
            SendMessageToPC(oPC, "You shrug the cloak off and settle back into yourself.");
        else
            SendMessageToPC(oPC, "You shrug the cloak off, but the mask has not finished with you.");
        return;
    }

    // --- put on ----------------------------------------------------------
    object oItem = CP_FindItem(oPC, "cp_cloak");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(8),
            "The cloak's colours run together into grey and the whole thing falls apart."))
        return;

    // Stash the true form once, and only if nothing else already has -- the Mask
    // may have got there first, and overwriting would strand the player wearing
    // whatever face they happened to have on.
    CP_FaceClaim(oPC, CP_FACE_CLOAK);

    SetLocalInt(oPC, CP_CLOAK_ON, TRUE);
    SendMessageToPC(oPC, "The cloak settles over your shoulders and your edges go soft.");

    if (CP_Now() >= GetLocalInt(oPC, CP_CLOAK_NEXT))
    {
        SetLocalInt(oPC, CP_CLOAK_NEXT, CP_Now() + 5);
        DelayCommand(1.0, ExecuteScript("cp_cloaktick", oPC));
    }
}
