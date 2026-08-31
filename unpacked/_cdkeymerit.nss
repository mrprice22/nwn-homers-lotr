// Merit tier conditional. Gates the two EmoteWand admin branches that move the
// merit economy - [Admin] Merit Awards and [Admin] Merit Redemptions - on
// admins.can_merit rather than admins.can_admin, so a DM can hold every other
// admin power without being able to award or fulfil merit. The authoritative
// half of the gate lives in the scripts themselves (merit_award_*.nss,
// merit_rfulfill.nss, merit_rcancel.nss); this one only hides the menu lines.
#include "admin_db"

int StartingConditional()
{
    return Admin_CanMerit(GetPCSpeaker());
}
