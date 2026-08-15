// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// (Re)spawn helper for Hallas the Shieldwarden, the Fighter-line giver. Fired
// from the area OnEnter wrapper (q_ftr_enter). No-ops gracefully until the admin
// places waypoint AP_fighterlineearly_1 in theprancingpo001 (see
// roadmap manual_steps) and never double-spawns.
#include "qline_gate_inc"
#include "q_ftr_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("ftr")) return;

    FTR_SpawnHallas();
}
