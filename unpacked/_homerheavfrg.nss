// "To. The Great Forge Of Numenor" - rest-menu teleport, Options of the
// Homeless.
//
// Target is the "heavensforgewp" waypoint in heavensfoundry (Numenor: The
// Great Forge Of Numenor) at (19.9, 28.4), standing just inside the northern
// entrance facing south down the hall toward the shafts of light, the fire
// bowls and HeavensArmorer's weapon store at the far end.
//
// Same shape as every other entry in this menu (_homerkalforge,
// _homerbasilisk, _homerbalrog, _homerweather, _homerdarklord): GetLastSpeaker,
// look up the tag, jump. Access is already gated one level up by _cdkeyhome on
// the "[Options of the Homeless]" link, so there is no check to repeat here.

void main()
{
    object oPC = GetLastSpeaker();
    object theWaypoint = GetWaypointByTag("heavensforgewp");

    if (!GetIsObjectValid(theWaypoint)) return;

    AssignCommand(oPC, JumpToLocation(GetLocation(theWaypoint)));
}
