// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// (Re)spawn helper for Halbarad, warden of the Grey Company, the Ranger-line
// giver. Fired from the area OnEnter wrapper (q_rng_enter). No-ops gracefully
// until the admin places waypoint AP_rangerlineearly_1 in rangerwaystation (see
// admin-action-required.md) and never double-spawns.
#include "q_rng_inc"

void main()
{
    RNG_SpawnKeeper();
}
