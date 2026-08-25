// The inverse of _cdkey: TRUE for everyone who is NOT an admin.
//
// Exists for exactly one job - picking which "Back." an ungated visitor to a
// SHARED submenu gets. The MW Teleports node (emotewand.dlg Entry10) is reached
// two ways: from Admin Options for an admin, and from the root-level
// [MW Teleports] entry, which sp_testkit opens to EVERY player on a tester
// realm. Its single Back. used to link to the admin menu unconditionally, so
// any tester could walk root -> [MW Teleports] -> Back. and land in the full
// Admin Options menu, which is ungated once reached because the only intended
// way in is gated. This is that hole's other half: with _cdkey on one Back. and
// this on the other, exactly one of them is ever visible and neither can hand
// out a menu its holder did not earn.
//
// Whitelist lives in the "admindb" campaign database (admins.can_admin), same
// as _cdkey - keys are seeded out of band and never ship inside the .mod.
//
// If you add another submenu shared between an admin path and an open one, gate
// its Back. the same way. Do NOT reuse this for anything that is meant to be
// "not an admin, therefore allowed" - it is a navigation helper, not a
// permission.
#include "admin_db"

int StartingConditional()
{
    return !Admin_CanAdmin(GetPCSpeaker());
}
