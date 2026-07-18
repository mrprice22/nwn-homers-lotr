// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// (Re)spawn helper for Lindir of the Hall of Fire, the Bard-line giver. Fired
// from the area OnEnter wrapper (q_bard_enter). No-ops gracefully until the
// admin places waypoint AP_bardlineearly_1 in rivendellupperha (Rivendell Upper
// Halls -- see roadmap manual_steps) and never double-spawns.
#include "q_bard_inc"

void main()
{
    BRD_SpawnMaster();
}
