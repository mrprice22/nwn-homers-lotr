// The Thirteenth Ent (roadmap: thirteenth-ent)
// (Re)spawn helper for Leaflock, the tree-still Ent of Fangorn. Fired from
// the Fangorn Forest OnEnter wrapper (q_ent_enter). No-ops gracefully until
// the admin places waypoint AP_thirteenthent_1 in Fangorn Forest
// (fangornforest) -- see roadmap manual_steps -- and never double-spawns.
#include "q_ent_inc"

void main()
{
    ENT_SpawnEnt();
}
