// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// (Re)spawn helper for Hallas the Shieldwarden, the Fighter-line giver. Fired
// from the area OnEnter wrapper (q_ftr_enter). No-ops gracefully until the admin
// places waypoint AP_fighterlineearly_1 in theprancingpo001 (see
// admin-action-required.md) and never double-spawns.
#include "q_ftr_inc"

void main()
{
    FTR_SpawnHallas();
}
