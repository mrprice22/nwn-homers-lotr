// Reply/entry gate for the forge "modify the item" (add-enchant) path: TRUE only
// when exactly one item sits on the anvil AND it still has value headroom to be
// enchanted upward (current worth below this forge's cap MODIFY_MAX). An item
// already at/over the cap can never gain an enchant - every add would be refused
// at commit - so the dialog routes it to the "at the limit, strip only" line
// instead of the yes/no add-enchant flow. Delegates the single-item check and the
// token priming to ForgeRefreshAnvilContext, so 100/104/105 are fresh for the
// chosen entry. Per-enchant overflow of an under-cap item is still caught at
// commit in modifyitem.nss; this only blocks the already-over-cap case.
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!ForgeRefreshAnvilContext(oPC))
        return FALSE;                       // not exactly one item on the anvil
    object oItem = GetLocalObject(oPC, "MODIFY_ITEM");
    int nWorth = ForgeItemValue(oItem);
    if (nWorth < 0)
        return FALSE;                       // valuation unavailable - refuse
    return nWorth < GetLocalInt(oPC, "MODIFY_MAX");
}
