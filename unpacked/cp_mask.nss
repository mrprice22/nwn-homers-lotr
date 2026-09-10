// cp_mask -- Crash Party: Mask of a Thousand Faces. Wave 1.
//
// Dispatched by tag from dmfi_activate.nss; OBJECT_SELF is the activating PC.
//
// Self-only. Rolls a new appearance, then puts the player's real one back after
// a fixed spell. Cosmetic only: SetCreatureAppearanceType changes the model, not
// a single stat, and is not EffectPolymorph -- so it cannot interact with the
// module's shapeshift item-merge machinery (shape_merge_inc.nss) and cannot be
// used to launder gear through a form change.
//
// The true appearance is stashed on the PC the FIRST time only, so stacking
// activations can never overwrite it with an already-masked value and strand
// someone as a dragon.

#include "cp_inc"

const string CP_MASK_TRUE = "CP_MASK_TRUEFORM";
const string CP_MASK_SEQ  = "CP_MASK_SEQ";

int CP_RandomFace()
{
    switch (Random(20))
    {
        case  0: return APPEARANCE_TYPE_BADGER;
        case  1: return APPEARANCE_TYPE_BAT;
        case  2: return APPEARANCE_TYPE_BOAR;
        case  3: return APPEARANCE_TYPE_CHICKEN;
        case  4: return APPEARANCE_TYPE_COW;
        case  5: return APPEARANCE_TYPE_DEER;
        case  6: return APPEARANCE_TYPE_GOBLIN_A;
        case  7: return APPEARANCE_TYPE_HALFLING_NPC_MALE;
        case  8: return APPEARANCE_TYPE_DWARF_NPC_MALE;
        case  9: return APPEARANCE_TYPE_ELF_NPC_FEMALE;
        case 10: return APPEARANCE_TYPE_GNOME_NPC_MALE;
        case 11: return APPEARANCE_TYPE_KOBOLD_A;
        case 12: return APPEARANCE_TYPE_ORC_A;
        case 13: return APPEARANCE_TYPE_PENGUIN;
        case 14: return APPEARANCE_TYPE_RAT;
        case 15: return APPEARANCE_TYPE_OX;
        case 16: return APPEARANCE_TYPE_TROLL;
        case 17: return APPEARANCE_TYPE_OGRE;
        case 18: return APPEARANCE_TYPE_WEREWOLF;
    }
    return APPEARANCE_TYPE_ZOMBIE;
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (CP_Spam(oPC, "cp_mask_cd", 3.0)) return;

    object oItem = CP_FindItem(oPC, "cp_mask");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(3),
            "The mask crumbles into a handful of painted dust."))
        return;

    // Remember the true form once and only once.
    if (!GetLocalInt(oPC, CP_MASK_TRUE + "_SET"))
    {
        SetLocalInt(oPC, CP_MASK_TRUE, GetAppearanceType(oPC));
        SetLocalInt(oPC, CP_MASK_TRUE + "_SET", TRUE);
    }

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_POLYMORPH), oPC);
    SetCreatureAppearanceType(oPC, CP_RandomFace());
    SendMessageToPC(oPC, "The mask settles over your face and something else looks out.");

    // Sequence guard: a later activation invalidates an earlier pending revert,
    // so re-masking before the timer runs out cannot snap you back early.
    int nSeq = GetLocalInt(oPC, CP_MASK_SEQ) + 1;
    SetLocalInt(oPC, CP_MASK_SEQ, nSeq);
    DelayCommand(90.0, ExecuteScript("cp_maskoff", oPC));
}
