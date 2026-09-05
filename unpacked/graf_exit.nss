// graf_exit.nss - leave the easel alcove and return to the Well proper.
//
// The alcove the easel stands in is fenced off from the rest of the area, and
// its only way out was an unscripted 1.2m area-transition trigger sitting
// directly under the arrival waypoint - a PC materialising on top of it could
// not path into it ("you cannot get close enough to enter"), which made the
// pocket a soft-lock. This reply does not involve the pathfinder at all.
//
// "respawn" is the Well of Eru's own arrival waypoint and is unique
// module-wide; portpchome.nss jumps to the same tag.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_Release(oPC);

    object oWP = GetWaypointByTag("respawn");
    if (!GetIsObjectValid(oWP)) return;

    DelayCommand(0.5, AssignCommand(oPC, ActionJumpToObject(oWP)));
}
