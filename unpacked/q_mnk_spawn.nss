// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// (Re)spawn helper for Orovan the Windless, the Monk-line giver. Fired from the
// area OnEnter wrapper (q_mnk_enter). No-ops gracefully until the admin places
// waypoint AP_monklineearly_1 in emynarnen (Emyn Arnen: Peak -- see roadmap
// manual_steps) and never double-spawns.
#include "q_mnk_inc"

void main()
{
    MNK_SpawnMaster();
}
