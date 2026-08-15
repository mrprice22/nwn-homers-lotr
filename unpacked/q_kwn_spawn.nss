// q_kwn_spawn - (re)spawn helper for the banner-stone on the Pelennor
// Fields (roadmap: knight-westernesse-quest). Fired from the field's
// OnEnter wrapper (q_kwn_ent1) and re-checked when the quest is accepted
// and when the standard is released. No-ops gracefully until the admin
// places waypoint AP_knightwest_1 (see the roadmap item manual_steps) and
// never double-spawns.
#include "qline_gate_inc"
#include "q_kwn_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("prsg")) return;

    QKWN_SpawnStone();
}
