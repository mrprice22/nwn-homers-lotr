// chisel_start -- dispatched from dmfi_activate (module OnActivateItem) when
// the Engraver's Chisel (tag WeaponChisel) is used. OBJECT_SELF is the
// activator (same ExecuteScript pattern as horn_summon). The rename itself
// completes in code_redeem (module OnPlayerChat) -- see chisel_inc.nss.
#include "chisel_inc"

void main()
{
    Chisel_Begin(OBJECT_SELF);
}
