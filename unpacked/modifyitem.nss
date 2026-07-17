#include "forge_inc"
#include "itemprocs"

void main()
{
    object oPC = GetPCSpeaker();

    //Transfer gold
    int iValue = GetLocalInt(oPC, "MODIFY_VALUE");
    int iDiff = GetLocalInt(oPC, "MODIFY_DIFF");
    object oItem = GetLocalObject(oPC, "MODIFY_ITEM");

    //Resolve the pending property up front: the cap below assesses the item
    //*with this property applied*, not the stale quote from a prior node.
    itemproperty ipNew = GetNewProperty(oItem);

    //Per-forge value ceiling: refuse enchants that would raise the item's
    //assessed value past this forge's cap (0 = uncapped), plus a hard backstop
    //at the global jailable ceiling so a missing/cleared area var can never let
    //a forge mint an item the login contraband scan would jail.
    //We assess the projected value directly — copy the item, add the pending
    //property, and price the copy (identified, non-plot via ForgeItemValue) —
    //so enforcement does NOT depend on the MODIFY_VALUE/MODIFY_DIFF locals an
    //earlier dialog node set; any stale-local path is still capped. A failed
    //valuation refuses rather than passing as cheap.
    int iMax = GetLocalInt(oPC, "MODIFY_MAX");
    // A high Appraise raises both this forge's per-tier cap (already folded into
    // MODIFY_MAX by isitemonanvil) and the global legal backstop below, by the
    // same amount, so lawful high-Appraise forging never trips the jail scan.
    int iBonus = ForgeAppraiseBonus(oPC);
    int iCurValue = ForgeItemValue(oItem);
    int iProjected = iCurValue;
    if (GetIsItemPropertyValid(ipNew))
        {
        object oHolder = ForgeHolder();
        object oProbe = GetIsObjectValid(oHolder)
            ? CopyItem(oItem, oHolder, TRUE) : OBJECT_INVALID;
        if (GetIsObjectValid(oProbe))
            {
            CustomAddProperty(oProbe, ipNew);
            iProjected = ForgeItemValue(oProbe);
            DestroyObject(oProbe);
            }
        else
            iProjected = -1;
        }
    if (iCurValue < 0 || iProjected < 0)
        {
        SpeakString("I cannot take the measure of this piece just now — try me "
            + "again in a moment.");
        return;
        }
    // The backstop is the UNIFORM legal ceiling (base + top boss-tier bonus,
    // see ForgeLegalMaxValue) + Appraise; the player's own boss-tier
    // entitlement is already enforced by the per-forge cap iMax below.
    if (iProjected > ForgeLegalMaxValue() + iBonus)
        {
        SpeakString("No forge in these lands may bind so much worth into one "
            + "piece — that lies beyond what the law allows. I'll not do it.");
        return;
        }
    if (iMax > 0 && iProjected > iMax)
        {
        SpeakString("I'm sorry — my forge cannot work this piece any further. I "
            + "dare not raise its worth past " + ForgeGold(iMax) + " gold. Take "
            + "it to a greater forge if you would push it beyond that.");
        return;
        }

    //Per-forge property-count ceiling (0 = uncapped), with a hard backstop at
    //the global jailable property limit. Replacing an existing property of the
    //same type doesn't grow the count, so it stays allowed.
    int iMaxProps = GetLocalInt(oPC, "MODIFY_MAX_PROPS");
    if (GetIsItemPropertyValid(ipNew)
        && !ForgePropMatchesExisting(oItem, ipNew))
        {
        int iProps = ForgeCountProps(oItem);
        // Uniform legal backstop (ForgeItemMaxProps = ForgeLegalMaxProps, incl.
        // the top boss-tier +1 slot, PLUS any Runes of Expansion bound into this
        // specific item); the per-forge/per-player cap iMaxProps below is what
        // actually limits characters who haven't earned the extra slots.
        int iItemMaxProps = ForgeItemMaxProps(oItem);
        if (iProps >= iItemMaxProps)
            {
            SpeakString("No forge may bind more than "
                + IntToString(iItemMaxProps) + " enchantments into one "
                + "piece — that is the limit of the law for this item. Have me "
                + "strike one from it first.");
            return;
            }
        if (iMaxProps > 0 && iProps >= iMaxProps)
            {
            SpeakString("This piece already carries " + IntToString(iMaxProps)
                + " enchantments — as much power as my forge dares bind into one "
                + "item. Have me strike an enchantment from it first, or seek a "
                + "greater forge.");
            return;
            }
        }

    //No refunds: refuse any change that would lower the item's assessed value.
    //The forges only enchant an item upward — never pay out for a downgrade.
    if (iDiff == -1)
        {
        SpeakString("I shape metal forward, not back — I'll not unmake the work "
            + "already in this piece for a handful of coin. Choose an enchantment "
            + "that betters it, or take it as it is.");
        return;
        }

    if (iDiff == 1 && GetGold(oPC) < iValue)
        {
        SpeakString("Oops.. looks like you don't have the gold for this.");
        return;
        }

    if (iDiff == 1)
        {
        TakeGoldFromCreature(iValue, oPC, TRUE);
        SetLocalInt(oItem, "FORGE_GP_INVESTED",
            GetLocalInt(oItem, "FORGE_GP_INVESTED") + (iValue * 80 / 100));
        }

    //Modify item
    if ( GetIsItemPropertyValid(ipNew))
        {
        CustomAddProperty(oItem, ipNew);
        // Enchanting changes the item's legality footprint — drop its "clean"
        // stamp so the next login contraband scan re-evaluates it.
        DeleteLocalInt(oItem, "FORGE_CLEAN");
        // If this lawful enchant carried the item above the default global
        // ceiling (the player's Appraise allowed it), record the lawful ceiling
        // on the item so the contraband scan / Warden never jail it later, even
        // if the bearer's Appraise changes or the item is traded. Keep the
        // highest ceiling ever applied.
        if (iProjected > ForgeLegalMaxValue())
            {
            int iCeil = ForgeLegalMaxValue() + iBonus;
            if (iCeil > GetLocalInt(oItem, FORGE_CEIL))
                SetLocalInt(oItem, FORGE_CEIL, iCeil);
            }
        }
}
