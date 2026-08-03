// q_hrp_spawn - (re)spawn helper for Della Heathertoes, the Harper contact
// at the Prancing Pony (roadmap: harper-scout-quest). Fired from the inn's
// OnEnter wrapper (q_hrp_ent1) and re-checked when the quest is accepted.
// No-ops gracefully until the admin places waypoint AP_harperscout_1 (see
// roadmap manual_steps) and never double-spawns.
#include "q_hrp_inc"

void main()
{
    QHRP_SpawnContact();
}
