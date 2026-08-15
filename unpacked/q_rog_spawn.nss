// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// (Re)spawn helper for Fenn the Shade, the Rogue-line giver. Fired from the
// area OnEnter wrapper (q_rog_enter). No-ops gracefully until the admin places
// waypoint AP_roguelineearly_1 in theprancingpo001 (see
// roadmap manual_steps) and never double-spawns.
#include "qline_gate_inc"
#include "q_rog_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("rog")) return;

    ROG_SpawnFenn();
}
