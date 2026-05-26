//::///////////////////////////////////////////////
//:: mw_hall_exit -- Hall of Legends OnExit handler.
//::
//:: When the last PC leaves: clear the occupancy lock and restore any
//:: swapped guide statues so the hall is fresh for the next visitor.
//:://////////////////////////////////////////////
#include "mw_unlock_inc"

void RestoreStatue(string sGuide, object oHallArea)
{
    string sLiveTag = "mw_" + sGuide + "_w";
    // Iterate all instances -- the world-spawn in e.g. Rivendell shares the tag,
    // so we must match by area rather than stopping at the first hit.
    int nIdx = 0;
    object oNPC = GetObjectByTag(sLiveTag, nIdx);
    while (GetIsObjectValid(oNPC))
    {
        if (GetArea(oNPC) == oHallArea)
        {
            location lLoc = GetLocation(oNPC);
            DestroyObject(oNPC);
            CreateObject(OBJECT_TYPE_PLACEABLE, "plc_statue1", lLoc, FALSE,
                         "mw_stat_" + sGuide);
            return;
        }
        oNPC = GetObjectByTag(sLiveTag, ++nIdx);
    }
}

void main()
{
    object oExiting = GetExitingObject();
    if (!GetIsPC(oExiting)) return;

    object oHallArea = OBJECT_SELF;

    // Stay if any PC is still in the hall (exiting player's GetArea already
    // reflects their new area, so they won't match here).
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        if (GetArea(oPC) == oHallArea) return;
        oPC = GetNextPC();
    }

    // Last PC has left -- clear the lock and restore all swapped statues.
    SetLocalInt(GetModule(), "MW_HALL_OCCUPIED", 0);
    int i;
    for (i = 0; i < MW_ROSTER_SIZE; i++)
        RestoreStatue(MW_GuideAt(i), oHallArea);
}
