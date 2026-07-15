// Beorn's Garden (roadmap: beorns-garden)
// (Re)spawn helper for the three honey hives. Fired from the OnEnter
// wrappers of beorn / carrok / carrokgreater (q_brn_ent1 / q_brn_ent2), so
// the hives stand ready by the time a player crosses the meadow. No-ops
// gracefully until the admin places waypoints AP_beorns-garden_1/2/3 (see
// admin-action-required.md) and never double-spawns.
#include "q_brn_inc"

void main()
{
    BRN_SpawnHives();
}
