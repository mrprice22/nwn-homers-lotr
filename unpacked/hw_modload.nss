// hw_modload - Harvest of Shadows: module-load half.
//
// ExecuteScript'd from onmoduleload.nss. Creates the tables (DDL belongs here,
// never on the login frame), reads the calendar, and - a few seconds later, so
// the load itself stays lean - re-plants the stored pumpkins, the boss rings,
// the Pumpkin King and the Gourd Board when inside the window.

#include "hw_inc"

void main()
{
    HW_InitDb();
    // Harvest Hearths are trophies: back every boot, whatever the date.
    DelayCommand(6.0, HW_RestoreHearths());
    int nPhase = HW_ReadPhase();
    SetLocalInt(GetModule(), "hw_phase", nPhase);
    if (nPhase == HW_PHASE_ACTIVE)
        DelayCommand(5.0, HW_Begin());
    else if (nPhase == HW_PHASE_CLAIM)
        DelayCommand(5.0, HW_SpawnBoard());
}
