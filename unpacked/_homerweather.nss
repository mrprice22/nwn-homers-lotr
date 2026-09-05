// "To. Weather Top" - rest-menu teleport, Options of the Homeless.
//
// Target is the "weathertop_tp" waypoint in the Weather Hills area
// (weatherhills, "Weather Hills") at (124.97, 65.59, 5.01), bearing 257.3,
// which is the approach below Amon Sul with the hill ahead of the arriving PC.
//
// This entry used to look up a waypoint tagged "weathertop", which does not
// exist anywhere in the module - GetWaypointByTag returned OBJECT_INVALID and
// JumpToLocation on an invalid location silently did nothing, so the menu
// option looked dead. The waypoint is now placed (weathertop_tp.utw.json plus
// the instance in weatherhills.git.json) and this points at it.
//
// Same shape as every other entry in this menu (_homerbasilisk, _homerbalrog,
// _homerkalforge, _homerdarklord): GetLastSpeaker, look up the tag, jump.
// Access is already gated one level up by _cdkeyhome on the "[Options of the
// Homeless]" link, so there is no check to repeat here.

void main()
{
    object oPC = GetLastSpeaker();
    object theWaypoint = GetWaypointByTag("weathertop_tp");

    if (!GetIsObjectValid(theWaypoint)) return;

    AssignCommand(oPC, JumpToLocation(GetLocation(theWaypoint)));
}
