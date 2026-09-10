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
// is or one will restore the other's borrowed one. CP_MASK_TRUEFORM is written
// only when it is not already set, by either item, and cp_login.nss restores
// from it at login -- which is what stops a player who logged out mid-swap from
// being stuck as a penguin forever. Appearance_Type is a SAVED .bic field while
// every timer that would undo it dies at logout; that asymmetry is the whole
// reason cp_login exists.

#include "cp_inc"

const string CP_CLOAK_ON   = "CP_CLOAK_ON";
const string CP_CLOAK_NEXT = "CP_CLOAK_NEXT";
const string CP_MASK_TRUE  = "CP_MASK_TRUEFORM";

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

        if (GetLocalInt(oPC, CP_MASK_TRUE + "_SET"))
        {
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectVisualEffect(VFX_IMP_POLYMORPH), oPC);
            SetCreatureAppearanceType(oPC, GetLocalInt(oPC, CP_MASK_TRUE));
            DeleteLocalInt(oPC, CP_MASK_TRUE);
            DeleteLocalInt(oPC, CP_MASK_TRUE + "_SET");
        }
        SendMessageToPC(oPC, "You shrug the cloak off and settle back into yourself.");
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
    if (!GetLocalInt(oPC, CP_MASK_TRUE + "_SET"))
    {
        SetLocalInt(oPC, CP_MASK_TRUE, GetAppearanceType(oPC));
        SetLocalInt(oPC, CP_MASK_TRUE + "_SET", TRUE);
    }

    SetLocalInt(oPC, CP_CLOAK_ON, TRUE);
    SendMessageToPC(oPC, "The cloak settles over your shoulders and your edges go soft.");

    if (CP_Now() >= GetLocalInt(oPC, CP_CLOAK_NEXT))
    {
        SetLocalInt(oPC, CP_CLOAK_NEXT, CP_Now() + 5);
        DelayCommand(1.0, ExecuteScript("cp_cloaktick", oPC));
    }
}
