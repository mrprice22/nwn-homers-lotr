// mw_style_0 -- set combat style 0 (default/balanced).
// Calculated for Peterson; Enlightened for Watts; Balanced for Campbell/McKenna;
// Guardian for Aurelius; Shadow for Jung.
void main()
{
    SetLocalInt(OBJECT_SELF, "MW_STYLE", 0);
    object oMaster = GetMaster();
    if (GetIsObjectValid(oMaster))
        FloatingTextStringOnCreature("Understood.", oMaster, FALSE);
}
