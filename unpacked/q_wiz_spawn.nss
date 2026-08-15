// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// (Re)spawn helper for Findegil the Grey, the Wizard-line giver. Fired from the
// area OnEnter wrapper (q_wiz_enter). No-ops gracefully until the admin places
// waypoint AP_wizardlineearly_1 in bagend001 (see the roadmap item manual_steps) and
// never double-spawns.
#include "qline_gate_inc"
#include "q_wiz_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("wiz")) return;

    WIZ_SpawnFindegil();
}
