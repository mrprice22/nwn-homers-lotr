// "To. Basilisk Lair" - rest-menu teleport, Options of the Homeless.
//
// Target is the "basilisklair" waypoint in area002 (Mirkwood: Crypt Lower),
// placed just inside the lower2crypt entry door and facing into the lair. That
// is the door you would walk in through from Mirkwood: Crypt, so the arrival
// reads as the lair entrance rather than a drop into the middle of it.
//
// Added for petrification UAT: the basilisks (Spell 485, SPELL_FLESH_TO_STONE)
// are the only in-game petrification source that is not the Castle Homeless
// test rig, and hunting one across Mirkwood on every retest was the slow part
// of the check. The Basilisk King is one more door on from here (lower2cata ->
// area003, Mirkwood: Crypt Chamber).
//
// Same shape as every other entry in this menu (_homerbalrog, _homerweather,
// _homerdarklord): GetLastSpeaker, look up the tag, jump.

void main()
{
    object oPC = GetLastSpeaker();
    object theWaypoint = GetWaypointByTag("basilisklair");

    if (!GetIsObjectValid(theWaypoint)) return;

    AssignCommand(oPC, JumpToLocation(GetLocation(theWaypoint)));
}
