// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// (Re)spawn helper for Naldor the Green, the Druid-line giver. Fired from the
// area OnEnter wrapper (q_drd_enter). No-ops gracefully until the admin places
// waypoint AP_druidlineearly_1 in rhosgobel (see roadmap manual_steps) and
// never double-spawns.
#include "q_drd_inc"

void main()
{
    DRD_SpawnKeeper();
}
