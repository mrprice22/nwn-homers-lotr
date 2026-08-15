// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// (Re)spawn helper for Naldor the Green, the Druid-line giver. Fired from the
// area OnEnter wrapper (q_drd_enter). No-ops gracefully until the admin places
// waypoint AP_druidlineearly_1 in rhosgobel (see roadmap manual_steps) and
// never double-spawns.
#include "qline_gate_inc"
#include "q_drd_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("drd")) return;

    DRD_SpawnKeeper();
}
