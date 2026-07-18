// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// (Re)spawn helper for Fenn the Shade, the Rogue-line giver. Fired from the
// area OnEnter wrapper (q_rog_enter). No-ops gracefully until the admin places
// waypoint AP_roguelineearly_1 in theprancingpo001 (see
// roadmap manual_steps) and never double-spawns.
#include "q_rog_inc"

void main()
{
    ROG_SpawnFenn();
}
