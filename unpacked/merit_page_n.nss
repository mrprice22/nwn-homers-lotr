// merit_page_n - Reply action: go to next page of player list.
#include "merit_db"
void main()
{
    object oDM = GetPCSpeaker();
    int nOff = GetLocalInt(oDM, "merit_page_off") + 9;
    SetLocalInt(oDM, "merit_page_off", nOff);
    Merit_BuildPage(oDM);
}
