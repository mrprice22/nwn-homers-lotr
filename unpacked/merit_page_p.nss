// merit_page_p - Reply action: go to previous page of player list.
#include "merit_db"
void main()
{
    object oDM = GetPCSpeaker();
    int nOff = GetLocalInt(oDM, "merit_page_off") - 9;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oDM, "merit_page_off", nOff);
    Merit_BuildPage(oDM);
}
