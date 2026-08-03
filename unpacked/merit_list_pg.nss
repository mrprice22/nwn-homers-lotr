// merit_list_pg - Reply action: enter Merit Awards player list (resets to page 1).
#include "merit_db"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_page_off", 0);
    Merit_BuildPage(oDM);
}
