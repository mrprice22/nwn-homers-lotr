// graf_up.nss - go up one level of the browser (looks -> kinds -> themes).
// One reply, not two, because the level is in graf_mode rather than the dlg.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    int nMode = GetLocalInt(oPC, "graf_mode");
    if (nMode > 0) nMode--;
    SetLocalInt(oPC, "graf_mode", nMode);
    SetLocalInt(oPC, "graf_page_off", 0);
    Graf_BuildPage(oPC);
}
