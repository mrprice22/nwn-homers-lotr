// fate_evt.nss - NUI event handler for the Shard of Fate bonus-roll prompt
// (lo-fate-token).  Registered per-window via NuiCreate's sEventScript in
// fate_inc.  Buttons send "click"; everything else is ignored.

#include "fate_inc"

void main()
{
    if (NuiGetEventType() != "click") return;
    object oPC = NuiGetEventPlayer();
    string sElem = NuiGetEventElement();
    if (sElem == "fspend")
        Fate_Spend(oPC);
    else if (sElem == "fkeep")
    {
        Fate_Close(oPC);
        SendMessageToPC(oPC, "You keep the Shard of Fate.");
    }
}
