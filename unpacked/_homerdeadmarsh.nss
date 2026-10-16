// "To. The Dead Marshes" - rest-menu teleport, Options of the Homeless.
//
// Harvest of Shadows: the Pumpkin King (tag hw_pking) wanders deadmarshes and
// is spawned at a random spot, so there is no fixed boss waypoint. Land on the
// area-entrance waypoint (WP_deadmarshes2*, the ones the transitions deliver
// players to) nearest the King while he is up, or on the north entrance
// (WP_deadmarshes2ithnorth) when he is not. Only WP_ landings are used: the
// mnx_ map-note pins also are waypoints, and mnx_Portdeadmarsh sits in the
// mausoleum doorway, which is where a nearest-waypoint pick left players stuck.
//
// Access is gated one level up by _cdkeyhome on the "[Options of the
// Homeless]" link (everyone on a tester realm, can_homeless on live), so there
// is no check to repeat here.

void main()
{
    object oPC = GetLastSpeaker();
    object oDest = GetWaypointByTag("WP_deadmarshes2ithnorth");
    object oKing = GetObjectByTag("hw_pking");

    if (GetIsObjectValid(oKing) && GetIsObjectValid(oDest)
        && GetArea(oKing) == GetArea(oDest))
    {
        int n = 1;
        object oNear = GetNearestObject(OBJECT_TYPE_WAYPOINT, oKing, n);
        while (GetIsObjectValid(oNear))
        {
            if (GetStringLeft(GetTag(oNear), 3) == "WP_") { oDest = oNear; break; }
            oNear = GetNearestObject(OBJECT_TYPE_WAYPOINT, oKing, ++n);
        }
    }

    if (!GetIsObjectValid(oDest)) return;

    AssignCommand(oPC, JumpToLocation(GetLocation(oDest)));
}
