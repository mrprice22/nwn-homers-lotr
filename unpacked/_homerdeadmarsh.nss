// "To. The Dead Marshes" - rest-menu teleport, Options of the Homeless.
//
// Harvest of Shadows: the Pumpkin King (tag hw_pking) wanders deadmarshes and
// is spawned at a random spot, so there is no fixed boss waypoint. Land on the
// Dead Marshes waypoint nearest the King while he is up, or on the north
// entrance (WP_deadmarshes2ithnorth) when he is not.
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
        object oNear = GetNearestObject(OBJECT_TYPE_WAYPOINT, oKing);
        if (GetIsObjectValid(oNear)) oDest = oNear;
    }

    if (!GetIsObjectValid(oDest)) return;

    AssignCommand(oPC, JumpToLocation(GetLocation(oDest)));
}
