#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    object oItem = GetLocalObject(oPC, "MODIFY_ITEM");
    object oCopy = GetLocalObject(oPC, "MODIFY_COPY");

    //Value both sides as identified, non-plot copies (ForgeItemValue) so an
    //unidentified or plot-flagged item can never quote a zero-cost enchant.
    int iCurrentValue = ForgeItemValue(oItem);
    int iNewValue = ForgeItemValue(oCopy);
    DestroyObject(oCopy);

    //Valuation unavailable: quote as a refused downgrade so modifyitem can
    //never apply the property for free.
    if (iCurrentValue < 0 || iNewValue < 0)
    {
        ForgeLog("calcmodvalue2: valuation failed for '" + GetName(oItem)
            + "' - refusing");
        SetLocalInt(oPC, "MODIFY_VALUE", 0);
        SetLocalInt(oPC, "MODIFY_DIFF", -1);
        SetCustomToken(101, "0");
        return;
    }

    //Either amount to pay, refund or no change
    int iValue = 0;
    int iDiff = 0;
    if (iNewValue > iCurrentValue)
        {
        iValue = iNewValue - iCurrentValue;
        iDiff = 1; //iValue is amount to pay
        }
    else if (iNewValue < iCurrentValue)
        {
        iValue = iCurrentValue - iNewValue;
        iDiff = -1; //iValue is refund
        };
    SetLocalInt(oPC, "MODIFY_VALUE", iValue);
    SetLocalInt(oPC, "MODIFY_DIFF", iDiff);
    SetCustomToken(101, ForgeGold(iValue));
    // Keep the worth tokens accurate for the cost prompt: 104 = current worth,
    // 107 = what the piece would be worth after this enchant. (105 = this
    // forge's cap, set on the anvil; isitemonanvil refreshes 104/106 each menu.)
    SetCustomToken(104, ForgeGold(iCurrentValue));
    SetCustomToken(107, ForgeGold(iNewValue));
}
