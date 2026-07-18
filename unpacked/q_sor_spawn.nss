// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// (Re)spawn helper for Erendis of the Drowned House, the Sorcerer-line giver.
// Fired from the area OnEnter wrapper (q_sor_enter). No-ops gracefully until
// the admin places waypoint AP_sorcererlineearly_1 in ruinsofannuminas (Ruins
// of Annuminas -- see roadmap manual_steps) and never double-spawns.
#include "q_sor_inc"

void main()
{
    SOR_SpawnMaster();
}
