// ru_back - reply action: return from an entry's detail view to the list.
//
// Rebuilds the page rather than trusting the row tokens to still hold this PC's
// page: SetCustomToken is module-global, so a second player browsing the sign
// at the same time would otherwise leave the first looking at their rows.
// Same reason brd_back.nss exists for the Roll of the Fallen.
#include "ru_db"
void main()
{
    RU_BuildPage(GetPCSpeaker());
}
