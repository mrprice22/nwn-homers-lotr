// graf_pick_2.nss - menu slot 2 was chosen. The browser has three levels and
// graf_mode says which one this is: a theme opens its kinds, a kind opens its
// looks, and a look repaints the canvas on the spot.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    string sSlot = GetLocalString(oPC, "graf_slot_2");
    if (sSlot == "") return;

    int nMode = GetLocalInt(oPC, "graf_mode");

    if (nMode == 2)
    {
        Graf_SetAppearance(oPC, StringToInt(sSlot));
        Graf_RenderFor(oPC);
        Graf_Summary(oPC);
        Graf_BuildAppPage(oPC);     // keep the list on screen, selection applied
        return;
    }

    SetLocalInt(oPC, "graf_page_off", 0);
    if (nMode == 1)
    {
        SetLocalString(oPC, "graf_cat", sSlot);
        SetLocalInt(oPC, "graf_mode", 2);
        Graf_BuildAppPage(oPC);
        return;
    }

    SetLocalString(oPC, "graf_theme", sSlot);
    SetLocalInt(oPC, "graf_mode", 1);
    Graf_BuildCatPage(oPC);
}
