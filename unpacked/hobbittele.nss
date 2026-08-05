// hobbittele.nss - Guardian of Light fast-travel destination: The Shire, Hobbiton.
//
// Cloned from breetele.nss (roadmap: concerning-pipeweed). Attached as the
// Script on the "The Shire -- Hobbiton." reply of goodtele.dlg. The waypoint
// tag "hobtele" ("Hobbiton Teleport") already exists in shirehobbiton001; the
// script resref is deliberately different from the tag so the two stay
// visually distinct. Ungated, like all twelve existing destinations.
void main()
{
object oPC = GetLastSpeaker();
object theWaypoint = GetWaypointByTag("hobtele");
if (!GetIsObjectValid(theWaypoint)) return;
location lHobbiton = GetLocation(theWaypoint);

AssignCommand(oPC, JumpToLocation(lHobbiton));
}
