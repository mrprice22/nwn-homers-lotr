// Admin Options conditional. The whitelist now lives in the "admindb" campaign
// database (admins.can_admin), not in source - keys are seeded out of band via
// bin/seed-admindb.sh and never ship inside the .mod.
#include "admin_db"

int StartingConditional()
{
    return Admin_CanAdmin(GetPCSpeaker());
}
