// dye_nui_evt.nss — NUI event handler for the Dye Studio window.
// Registered per-window via the sEventScript arg of NuiCreate in dye_nui_open.
#include "dye_nui_inc"

void main() {
    if (NuiGetEventType() != "click") return;

    object oPC = NuiGetEventPlayer();
    string e = NuiGetEventElement();

    if (e == "bclose") {
        NuiDestroy(oPC, GetLocalInt(oPC, DYE_TOK));
        DyeCleanup(oPC);
        return;
    }
    if (e == "bshape") {
        // Hand off to the ZEP station for model / shield / weapon reshaping.
        NuiDestroy(oPC, GetLocalInt(oPC, DYE_TOK));
        DyeCleanup(oPC);
        AssignCommand(oPC, ActionStartConversation(oPC, "x0_skill_ctrap", TRUE, FALSE));
        return;
    }
    if (e == "brev") { DyeRevert(oPC); return; }

    if (e == "slc") { DyeSelectSlot(oPC, INVENTORY_SLOT_CHEST); return; }
    if (e == "slh") { DyeSelectSlot(oPC, INVENTORY_SLOT_HEAD);  return; }
    if (e == "slk") { DyeSelectSlot(oPC, INVENTORY_SLOT_CLOAK); return; }

    if (GetStringLeft(e, 2) == "ch") {
        DyeSelectChannel(oPC, StringToInt(GetSubString(e, 2, GetStringLength(e) - 2)));
        return;
    }
    if (GetStringLeft(e, 2) == "sw") {
        int nIdx = StringToInt(GetSubString(e, 2, GetStringLength(e) - 2));
        DyeApply(oPC, nIdx);
        SetLocalInt(oPC, DYE_SEL, nIdx);
        DyeRefresh(oPC);
        return;
    }
}
