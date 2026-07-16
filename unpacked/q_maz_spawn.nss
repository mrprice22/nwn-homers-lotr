// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// (Re)spawn helper for Frar's shade and the three seal-braziers. Fired from
// the OnEnter wrappers of chamberofrecords / balinstomb (q_maz_ent1 /
// q_maz_ent2), so everything stands ready by the time a player crosses the
// chamber. No-ops gracefully until the admin places waypoints
// AP_mazarbul20_1..4 (see admin-action-required.md) and never double-spawns.
#include "q_maz_inc"

void main()
{
    MAZ_SpawnAll();
}
