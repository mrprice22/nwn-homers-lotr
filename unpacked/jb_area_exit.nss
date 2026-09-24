// jb_area_exit.nss - cash in jukebox listening credit when a player leaves.
//
// Reached two ways, because the eight jukebox areas did not agree on who owned
// their OnExit:
//
//   1. DIRECTLY, as the area's OnExit, for the three that had none
//      (thewelloferu, greendragoninn, laketownthetipss). GetExitingObject()
//      is the player.
//   2. DELEGATED, via ExecuteScript from the OnExit those areas already had
//      (cleanup, d_purge), which pass the player in the jb_leaver local because
//      the exiting-object event data does not survive an ExecuteScript.
//
// Chaining the other way round - taking over OnExit and calling the previous
// owner - was the alternative and is worse: getting the mapping wrong would
// silently stop encounter and loot cleanup in a tavern, which is a much larger
// failure than a missed buff.
#include "jb_buff_inc"

void main()
{
    object oArea = OBJECT_SELF;

    object oPC = GetLocalObject(oArea, "jb_leaver");
    if (GetIsObjectValid(oPC))
        DeleteLocalObject(oArea, "jb_leaver");
    else
        oPC = GetExitingObject();

    if (!GetIsPC(oPC)) return;

    JB_OnLeaveArea(oPC, oArea);
}
