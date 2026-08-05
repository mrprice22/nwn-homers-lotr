// ru_menu - reply action: back to the sign's opening menu.
// Rebuilds the pending count so it is current even mid-conversation.
#include "ru_db"
void main()
{
    RU_BuildMenu(GetPCSpeaker());
}
