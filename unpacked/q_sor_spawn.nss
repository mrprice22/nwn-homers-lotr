// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// (Re)spawn helper for Erendis of the Drowned House, the Sorcerer-line giver.
// Fired from the area OnEnter wrapper (q_sor_enter). No-ops gracefully until
// the admin places waypoint AP_sorcererlineearly_1 in ruinsofannuminas (Ruins
// of Annuminas -- see roadmap manual_steps) and never double-spawns.
#include "qline_gate_inc"
#include "q_sor_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("sor")) return;

    SOR_SpawnMaster();
}
