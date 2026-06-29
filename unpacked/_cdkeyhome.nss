// "Options for the Homeless" conditional. Whitelist lives in the "admindb"
// campaign database (admins.can_homeless), not in source.
#include "admin_db"

int StartingConditional()
{
    return Admin_CanHomeless(GetPCSpeaker());
}
