// lw_open.nss - open the Loot Wishlist window (Loot Overhaul Phase 6).
// Action script of the rest menu's "Loot wishlist..." reply (emotewand.dlg);
// the reply has no entry after it, so the conversation ends and the window opens.

#include "lw_nui"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsPC(oPC)) oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    LW_Open(oPC);
}
