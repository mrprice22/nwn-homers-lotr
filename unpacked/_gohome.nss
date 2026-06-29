// _gohome — rest-menu "Home" teleport action. Jumps the PC to their house's
// home waypoint, looked up by CD key in the admindb houses table. One home per
// CD key, so this is unambiguous and reusable for every player house.
#include "admin_db"
void main()
{
    object oPC = GetPCSpeaker();
    string sWP = Admin_GetHomeWP(oPC);
    if (sWP == "") return;

    object oWay = GetWaypointByTag(sWP);
    if (!GetIsObjectValid(oWay)) return;

    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, JumpToObject(oWay));
}
