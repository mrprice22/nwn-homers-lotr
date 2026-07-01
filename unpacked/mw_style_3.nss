// mw_style_3 -- set combat style 3 (Counterspell).
// Caster guides stand ground and counter enemy spells instead of nuking/healing.
// Used by Peterson, Watts, Campbell, McKenna, and Aurelius.
#include "mw_counter_inc"
void main()
{
    SetLocalInt(OBJECT_SELF, "MW_STYLE", 3);
    object oMaster = GetMaster();
    if (GetIsObjectValid(oMaster))
        FloatingTextStringOnCreature("I will turn their magic against them.", oMaster, FALSE);
}
