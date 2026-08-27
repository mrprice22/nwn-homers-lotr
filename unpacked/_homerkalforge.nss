// "To. Kallrist Crypt Forge" - rest-menu teleport, Options of the Homeless.
//
// Target is the "kallristforgewp" waypoint in kallristcryptlow (Kallrist
// Crypt, lower level) at (85, 125), standing in the forge chamber facing the
// Anvil of Wonder (85, 130) and Kallrist Smith (89, 128), with the fell beast
// guardian balsum (badass_2) about 11m off at (94.9, 129.2).
//
// This is the deepest room in the module's longest locked chain, and every
// link of it has to be re-walked to reach the forge or the guardian:
// Kallrist Outer Banks -> upper crypt -> solve the elemental-pillar riddle for
// kalcryptkey001 -> kallupper2riddledoor (which re-locks 8s after each use)
// -> central chamber -> five trapped doors down the lower crypt. Testing the
// third forge tier, the Horn of the Fell Beast drop, or the crypt riddle's own
// payout meant redoing all of it each time.
//
// Same shape as every other entry in this menu (_homerbasilisk, _homerbalrog,
// _homerweather, _homerdarklord): GetLastSpeaker, look up the tag, jump.
// Access is already gated one level up by _cdkeyhome on the "[Options of the
// Homeless]" link, so there is no check to repeat here.

void main()
{
    object oPC = GetLastSpeaker();
    object theWaypoint = GetWaypointByTag("kallristforgewp");

    if (!GetIsObjectValid(theWaypoint)) return;

    AssignCommand(oPC, JumpToLocation(GetLocation(theWaypoint)));
}
