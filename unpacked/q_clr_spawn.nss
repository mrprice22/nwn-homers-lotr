// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// (Re)spawn helper for Aldamir, Keeper of the Flame, the Cleric-line giver.
// Fired from the area OnEnter wrapper (q_clr_enter). No-ops gracefully until the
// admin places waypoint AP_clericlineearly_1 in templeofilluvata (see
// roadmap manual_steps) and never double-spawns.
#include "q_clr_inc"

void main()
{
    CLR_SpawnKeeper();
}
