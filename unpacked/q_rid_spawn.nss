// The Riddle Game (roadmap: riddle-game)
// (Re)spawn helper for the whispering wretch in Bree Cave. Fired from the
// area's OnEnter wrapper (q_rid_enter), so the wretch is always waiting by
// the time a player crosses the cave. No-ops gracefully until the admin
// places waypoint AP_riddle-game_1 in breecave (see admin-action-required.md)
// and never double-spawns. The placed Gollum boss is a separate blueprint.
void main()
{
    object oWP = GetWaypointByTag("AP_riddle-game_1");
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag("q_rid_wretch")))
        CreateObject(OBJECT_TYPE_CREATURE, "q_rid_wretch", GetLocation(oWP));
}
