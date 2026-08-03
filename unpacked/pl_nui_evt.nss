// pl_nui_evt - NUI event handler for the Party Loot Roll window.
// Registered per-window via the sEventScript arg of NuiCreate in inc_partyloot.
#include "inc_partyloot"

void main()
{
    if (NuiGetEventType() != "click") return;   // buttons send "click"

    object oPC = NuiGetEventPlayer();
    string sElem = NuiGetEventElement();

    int nChoice;
    if      (sElem == "btn_need")  nChoice = PL_NEED;
    else if (sElem == "btn_greed") nChoice = PL_GREED;
    else if (sElem == "btn_pass")  nChoice = PL_PASS;
    else return;

    PL_Record(oPC, nChoice);
}
