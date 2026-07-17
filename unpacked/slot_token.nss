//::///////////////////////////////////////////////
//:: slot_token -- Rune of Expansion (item tag SlotToken).
//::
//:: A consumable that binds +1 forge property slot into ONE targeted item,
//:: raising how many enchantments the forge (and the contraband/legality law)
//:: will allow on THAT item by one, up to FORGE_TOKEN_MAX_SLOTS runes.
//::
//:: Dispatched from dmfi_activate's OnActivateItem branch, which stamps the
//:: activated rune and its target onto the activator before ExecuteScript:
//::   SLOT_TOKEN_ITEM   = GetItemActivated()        (the rune)
//::   SLOT_TOKEN_TARGET = GetItemActivatedTarget()  (the item to expand)
//:: OBJECT_SELF is the activator (oActivator).
//::
//:: The earned count lives on the target as item-local int FORGE_EXTRA_SLOTS
//:: (persists with the item in the .bic, exactly like FORGE_CEIL), so the
//:: entitlement is intrinsic to the item and travels with it when traded.
//:: See forge_inc.nss (ForgeItemExtraSlots / ForgeItemMaxProps) for how the
//:: forge and the legality scan read it. Drop-source/rarity is an admin
//:: decision (see admin-action-required.md).  roadmap: item-slot-tokens
//:://////////////////////////////////////////////

#include "forge_inc"

void main()
{
    object oPC     = OBJECT_SELF;
    object oTarget = GetLocalObject(oPC, "SLOT_TOKEN_TARGET");
    object oToken  = GetLocalObject(oPC, "SLOT_TOKEN_ITEM");
    DeleteLocalObject(oPC, "SLOT_TOKEN_TARGET");
    DeleteLocalObject(oPC, "SLOT_TOKEN_ITEM");

    if (!GetIsPC(oPC))
        return;

    // Must target an item...
    if (!GetIsObjectValid(oTarget)
        || GetObjectType(oTarget) != OBJECT_TYPE_ITEM)
    {
        FloatingTextStringOnCreature("Point the rune at an item in your pack to "
            + "bind its power into it.", oPC, FALSE);
        return;
    }
    // ...that you actually carry...
    if (GetItemPossessor(oTarget) != oPC)
    {
        FloatingTextStringOnCreature("You may only expand an item you carry.",
            oPC, FALSE);
        return;
    }
    // ...and not the rune itself.
    if (oTarget == oToken)
    {
        FloatingTextStringOnCreature("The rune cannot be bound into itself.",
            oPC, FALSE);
        return;
    }

    // Already fully expanded? Do not consume the rune.
    int nCur = ForgeItemExtraSlots(oTarget);
    if (nCur >= FORGE_TOKEN_MAX_SLOTS)
    {
        FloatingTextStringOnCreature("The " + GetName(oTarget) + " already holds "
            + "all the expansion it can bear (" + IntToString(FORGE_TOKEN_MAX_SLOTS)
            + " extra slots). The rune stays whole.", oPC, FALSE);
        return;
    }

    // Consume exactly one rune (decrement a stack, else destroy the item).
    if (GetIsObjectValid(oToken))
    {
        if (GetItemStackSize(oToken) > 1)
            SetItemStackSize(oToken, GetItemStackSize(oToken) - 1);
        else
            DestroyObject(oToken);
    }

    // Bind the extra slot into the target. FORGE_EXTRA_SLOTS is read by the
    // forge (modifyitem via ForgeItemMaxProps) and the legality law alike, so
    // the item is never jailed for the extra enchantment it may now hold.
    int nNew = nCur + 1;
    SetLocalInt(oTarget, FORGE_EXTRA_SLOTS, nNew);
    // Footprint of what is lawful changed (only loosens) -- drop any stale
    // "clean" stamp so the next contraband scan re-reads the item cleanly.
    DeleteLocalInt(oTarget, "FORGE_CLEAN");

    FloatingTextStringOnCreature("The rune sinks into the " + GetName(oTarget)
        + ", widening its lattice. A forge may now bind " + IntToString(nNew)
        + " enchantment" + (nNew == 1 ? "" : "s") + " into it beyond the common "
        + "limit (" + IntToString(nNew) + " of " + IntToString(FORGE_TOKEN_MAX_SLOTS)
        + " runes bound).", oPC, FALSE);
}
