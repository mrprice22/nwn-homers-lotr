// Admin Options conditional (alternate menu entry). Whitelist lives in the
// "admindb" campaign database (admins.can_admin), not in source.
#include "admin_db"

int StartingConditional()
{
    return Admin_CanAdmin(GetPCSpeaker());
}
