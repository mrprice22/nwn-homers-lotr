// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// (Re)spawn helper for Hallas the Oathkeeper, the Paladin-line giver. Fired
// from the area OnEnter wrapper (q_pld_enter). No-ops gracefully until the
// admin places waypoint AP_paladinlineearly_1 in area005 (Minas Tirith: Keep --
// see roadmap manual_steps) and never double-spawns.
#include "q_pld_inc"

void main()
{
    PLD_SpawnKeeper();
}
