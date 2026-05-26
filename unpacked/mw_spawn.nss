// mw_spawn.nss
// Spawns Meaningwave NPCs at their designated waypoints.
// Called from onmoduleload.nss on module start.
// To place an NPC: put a waypoint using blueprint mw_spawn in the area,
// set its Tag to the value in the table below, then repack.
//
// Tag              -> Creature resref    -> Area
// MW_SPAWN_PETERSON   mw_peterson_w       rivendellupperha (Upper Halls Rivendell)
// MW_SPAWN_CAMPBELL   mw_campbell_w       balinstomb (Bolin's Tomb)
// MW_SPAWN_JUNG       mw_jung_w           cryptsofthelosts (Crypts of the Lost)
// MW_SPAWN_AURELIUS   mw_aurelius_w       gwaththrone (Gwaththrone)
// MW_SPAWN_AKIRA      mw_akira            hallofleg (Hall of Legends)
// MW_SPAWN_JOCKO      mw_jocko_w          helmsdeep001 (Helm's Deep)
// MW_SPAWN_MCKENNA    mw_mckenna_w        northernforestso (Northern Forests)
// MW_SPAWN_WATTS      mw_watts_w          oldforest001 (Old Forest)

void SpawnAtWaypoint(string sWPTag, string sResRef)
{
    object oWP = GetWaypointByTag(sWPTag);
    if (oWP == OBJECT_INVALID) return;
    if (GetObjectByTag(sResRef) != OBJECT_INVALID) return;
    CreateObject(OBJECT_TYPE_CREATURE, sResRef, GetLocation(oWP));
}

void main()
{
    SpawnAtWaypoint("MW_SPAWN_PETERSON", "mw_peterson_w");
    SpawnAtWaypoint("MW_SPAWN_CAMPBELL", "mw_campbell_w");
    SpawnAtWaypoint("MW_SPAWN_JUNG",     "mw_jung_w");
    SpawnAtWaypoint("MW_SPAWN_AURELIUS", "mw_aurelius_w");
    SpawnAtWaypoint("MW_SPAWN_AKIRA",    "mw_akira");
    SpawnAtWaypoint("MW_SPAWN_JOCKO",    "mw_jocko_w");
    SpawnAtWaypoint("MW_SPAWN_MCKENNA",  "mw_mckenna_w");
    SpawnAtWaypoint("MW_SPAWN_WATTS",    "mw_watts_w");
}
