// sp_testkit - dialogue conditional: show the [MW Teleports] root entry in the
// rest menu. TRUE only on a tester realm (SP_TESTER_KIT).
//
// Deliberately NO admin fallback. On a live season an admin already reaches the
// same node through Admin Options -> MW Teleports, so an admin-visible copy at
// the root would just be a duplicate entry in their menu. See sp_testkit_inc.
#include "sp_testkit_inc"

int StartingConditional()
{
    return SP_TesterKit();
}
