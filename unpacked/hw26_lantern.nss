// hw26_lantern - Lantern of the Restless Dead: Call the Restless (activated),
// 2 per 90 real minutes. Three Pumpkin-Born Skeletons rise to fight for the
// wearer for 3 minutes - created, not summoned, so the summon slot stays free.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "restless", "Call the Restless", 2)) return;
    HW_SpawnAllySkeletons(oPC, GetLocation(oPC), 3, 180.0);
}
