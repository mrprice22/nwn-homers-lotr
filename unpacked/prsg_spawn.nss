// Prestige-order hub (roadmap: prestige-trainer-hub)
// (Re)spawn helper for Halmir the Grey, Keeper of the Old Orders. Fired
// from the Well of Eru OnEnter wrapper (prsg_enter) so he stands ready by
// the time a player reaches the well. No-ops gracefully until the admin
// places waypoint AP_prestigehub_1 (see the roadmap item manual_steps) and
// never double-spawns.
#include "prsg_inc"

void main()
{
    PRSG_SpawnTrainer();
}
