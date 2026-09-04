// Weather Top -> the hidden court (roadmap: forbidden-realms-key-tier)
//
// OnEnter for the area026 trigger tagged wtop_hiddencave. Per the trigger's own
// toolset Comment this is deliberately NOT a real area transition:
//
//   "Manual hidden version of an area transition so it doesnt show up when
//    players press TAB: uses script on trigger enter teleports player to
//    wp_wtop2court (waypoint)"
//
// A real transition would list "Weather Top's Hidden Court" in the TAB map and
// give the secret away to anyone who had never found the cave. A scripted jump
// costs the player nothing and shows nothing.
//
// The whole party is NOT dragged along: each character walks into the cave
// under their own steam, the same as any door. The way back out is the ordinary
// area transition on the court side (door wtopcourt2wtop -> waypoint
// wtopcourt2wtop here), so this is never a one-way trip.

const string WTOP_COURT_WP = "wp_wtop2court";

void main()
{
    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;

    object oWP = GetWaypointByTag(WTOP_COURT_WP);
    if (!GetIsObjectValid(oWP)) return;      // area028 not built yet: no-op

    AssignCommand(oPC, ActionJumpToLocation(GetLocation(oWP)));
}
