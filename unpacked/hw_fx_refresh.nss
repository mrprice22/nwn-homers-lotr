// hw_fx_refresh - re-sync the Harvest of Shadows prize effects on OBJECT_SELF
// (a PC) after an equip or unequip. Delayed a moment because during the
// unequip event the item is still in its slot.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    DelayCommand(0.3, HW_RefreshPrizeFx(oPC));
}
