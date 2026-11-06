// gem_login.nss - Loot Overhaul Phase 5: start the login socket pass.
// OBJECT_SELF = the PC (ExecuteScript from mod_cliententer).  No database work,
// so it stays off the login frame's critical path (memory: DDL off the login frame).
#include "gem_inc"

void main()
{
    Gem_BeginScan(OBJECT_SELF);
}
