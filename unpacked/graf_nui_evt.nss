// graf_nui_evt.nss - NUI event handler for the graffiti name/description form.
// Registered per-window via the sEventScript arg of NuiCreate in graf_nui_open.
#include "graf_nui_inc"
void main()
{
    if (NuiGetEventType() != "click") return;

    object oPC = NuiGetEventPlayer();
    string e = NuiGetEventElement();

    if (e == "bsave")  { Graf_NuiSave(oPC); return; }
    if (e == "bclose")
    {
        Graf_NuiSave(oPC);          // closing keeps what they typed
        NuiDestroy(oPC, GetLocalInt(oPC, GRAF_NUI_TOK));
        DeleteLocalInt(oPC, GRAF_NUI_TOK);
        return;
    }
}
