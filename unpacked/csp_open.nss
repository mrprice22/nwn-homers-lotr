// csp_open.nss - open the caster spell picker for OBJECT_SELF.
//
// One entry point for every caller: the level-up hook (csp_lvl) and the
// rest-finished hook (on_mod_rest), both via ExecuteScript on the PC. The
// GetPCSpeaker fallback is kept for a dialog action script, should one ever
// want to open the picker from an NPC.
//
// Re-derives the entitlement first, which is also what pays a character that
// levelled past 40 before this feature existed (see CSP_EnsureAllotment).

#include "csp_nui"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) oPC = GetPCSpeaker();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    if (CSP_PickerClass(oPC) == CLASS_TYPE_INVALID) return;

    CSP_EnsureAllotment(oPC);
    CSP_Open(oPC);
}
