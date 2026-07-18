// Concerning Hobbits (roadmap: concerning-hobbits)
// (Re)spawn helper for Odo Proudfoot, the Hobbiton genealogist. Fired from
// the area OnEnter wrapper (q_hob_enter). No-ops gracefully until the admin
// places waypoint AP_concerninghobbits_1 in shirehobbiton001 (see
// roadmap manual_steps) and never double-spawns.
void main()
{
    object oWP = GetWaypointByTag("AP_concerninghobbits_1");
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag("q_hob_odo")))
        CreateObject(OBJECT_TYPE_CREATURE, "q_hob_odo", GetLocation(oWP));
}
