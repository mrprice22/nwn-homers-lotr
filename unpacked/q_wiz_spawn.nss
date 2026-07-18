// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// (Re)spawn helper for Findegil the Grey, the Wizard-line giver. Fired from the
// area OnEnter wrapper (q_wiz_enter). No-ops gracefully until the admin places
// waypoint AP_wizardlineearly_1 in bagend001 (see admin-action-required.md) and
// never double-spawns.
#include "q_wiz_inc"

void main()
{
    WIZ_SpawnFindegil();
}
