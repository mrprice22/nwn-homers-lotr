// The Forbidden Realms (roadmap: forbidden-realms-key-tier)
// OnUsed for the barrow-gate placeable (q_frk_gate.utp). The gate's local
// string FRK_DEST (set when q_frk_inc spawns it) names the waypoint it leads
// to; outbound use demands the Forbidden Realms Key, the return trip does not.
#include "q_frk_inc"

void main()
{
    FRK_UseGate(OBJECT_SELF, GetLastUsedBy());
}
