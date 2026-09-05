// graf_cats.nss - open the browser at level 1: the nine themes.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    SetLocalInt(oPC, "graf_mode", 0);
    SetLocalInt(oPC, "graf_page_off", 0);
    Graf_BuildThemePage(oPC);
}
