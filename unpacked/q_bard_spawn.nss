// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// (Re)spawn helper for Lindir of the Hall of Fire, the Bard-line giver. Fired
// from the area OnEnter wrapper (q_bard_enter). No-ops gracefully until the
// admin places waypoint AP_bardlineearly_1 in rivendellupperha (Rivendell Upper
// Halls -- see roadmap manual_steps) and never double-spawns.
#include "qline_gate_inc"
#include "q_bard_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("bard")) return;

    BRD_SpawnMaster();
}
