// The Miller's Other Son -- (re)spawn helper for the quest NPCs. Fired on
// quest accept, on the miller's stage-1 reminder line, and on the peddler's
// quest greeting, so a character mid-quest can always find their marks even
// after another player dealt with them or the server rebooted.
//
// No-ops gracefully until the admin places the waypoints in the toolset
// (see admin-action-required.md), and never double-spawns:
//   AP_millerotherson_1 (tharbadbridge)  -> Tolly the Peddler
//   AP_millerotherson_2 (thardbadeast)   -> the cult leader
void main()
{
    object oWP = GetWaypointByTag("AP_millerotherson_1");
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag("mos2_peddler")))
        CreateObject(OBJECT_TYPE_CREATURE, "mos2_peddler", GetLocation(oWP));

    oWP = GetWaypointByTag("AP_millerotherson_2");
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag("MillerCultLeader")))
        CreateObject(OBJECT_TYPE_CREATURE, "mos2_leader", GetLocation(oWP));
}
