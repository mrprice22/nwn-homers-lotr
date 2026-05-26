// mw_style_1 -- set combat style 1 (aggressive/offensive).
// Aggressive for Peterson; Guardian for Watts; Combat for Campbell/McKenna;
// Offensive for Aurelius; Warrior for Jung.
void main()
{
    SetLocalInt(OBJECT_SELF, "MW_STYLE", 1);
    object oMaster = GetMaster();
    if (GetIsObjectValid(oMaster))
        FloatingTextStringOnCreature("As you say.", oMaster, FALSE);
}
