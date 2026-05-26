#include "mw_spawn_inc"

void main()
{
    ExecuteScript("d_cleartrash", OBJECT_SELF);
    MWSpawnAtWaypoint("MW_SPAWN_MCKENNA", "mw_mckenna_w");
}
