// don_cheat_close.nss
// OnClosed for the Well of Eru Donations Chest (tag x2_easy_Chest2ff).
// Re-stocks the best-in-slot cheat table every time the chest is shut, so any
// item a player just took is back for the next visitor - one copy, never more.
// Master switch: DON_CHEAT_ENABLED in don_cheat_inc.nss.
#include "don_cheat_inc"

void main()
{
    DonCheatRestock(OBJECT_SELF);
}
