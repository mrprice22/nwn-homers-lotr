// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// (Re)spawn helper for Halbarad, warden of the Grey Company, the Ranger-line
// giver. Fired from the area OnEnter wrapper (q_rng_enter). No-ops gracefully
// until the admin places waypoint AP_rangerlineearly_1 in rangerwaystation (see
// roadmap manual_steps) and never double-spawns.
#include "qline_gate_inc"
#include "q_rng_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("rng")) return;

    RNG_SpawnKeeper();
}
