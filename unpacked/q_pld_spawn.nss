// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// (Re)spawn helper for Hallas the Oathkeeper, the Paladin-line giver. Fired
// from the area OnEnter wrapper (q_pld_enter). No-ops gracefully until the
// admin places waypoint AP_paladinlineearly_1 in area005 (Minas Tirith: Keep --
// see roadmap manual_steps) and never double-spawns.
#include "qline_gate_inc"
#include "q_pld_inc"

void main()
{
    // Pulled back 2026-08-14 for creative rework -- see qline_gate_inc.nss.
    if (QL_LineOff("pld")) return;

    PLD_SpawnKeeper();
}
