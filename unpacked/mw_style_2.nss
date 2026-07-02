// mw_style_2 -- set combat style 2 (support-heavy/zen).
// Zen Strike for Watts; Healer for Campbell/McKenna.
// Not used by Peterson, Aurelius, or Jung.
void main()
{
    SetLocalInt(OBJECT_SELF, "MW_STYLE", 2);
    DeleteLocalInt(OBJECT_SELF, "MW_CTR_AUTOMELEE");
    DeleteLocalInt(OBJECT_SELF, "MW_CTR_STREAK");
    object oMaster = GetMaster();
    if (GetIsObjectValid(oMaster))
        FloatingTextStringOnCreature("I will see to it.", oMaster, FALSE);
}
