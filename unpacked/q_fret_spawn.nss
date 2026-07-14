// Ferny's Return -- fired on the guard's stage-1 reminder line. Re-spawns the
// impostor if another player already dealt with him (or the server rebooted),
// so a character mid-quest can always find their mark. No-ops until the admin
// places waypoint AP_ferny_return_1, and never double-spawns.
void main()
{
    object oWP = GetWaypointByTag("AP_ferny_return_1");
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag("fret_impostor")))
        CreateObject(OBJECT_TYPE_CREATURE, "fret_impostor", GetLocation(oWP));
}
