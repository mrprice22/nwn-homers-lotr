#include "mw_spawn_inc"

void main()
{
    ExecuteScript("d_cleartrash", OBJECT_SELF);
    MWSpawnAtWaypoint("MW_SPAWN_JOCKO", "mw_jocko_w");
}
