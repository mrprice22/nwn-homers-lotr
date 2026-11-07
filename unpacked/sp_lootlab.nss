// sp_lootlab - dialogue conditional: show the [Loot Lab] root entry in the rest
// menu. TRUE only on a tester realm (SP_TESTER_KIT) - every player there can
// roll, restock and grant loot to test the Season 3 Loot Overhaul.
//
// Deliberately NO admin fallback, for the same reason as sp_testkit: on a live
// season an admin already reaches the same node through Admin Options ->
// [Admin] Loot Lab. The Loot Lab actions re-check through LL_Authorised
// (lootlab_inc), which admits an admin anywhere and anyone on a tester realm.
#include "sp_testkit_inc"

int StartingConditional()
{
    return SP_TesterKit();
}
