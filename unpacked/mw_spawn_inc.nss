// mw_spawn_inc.nss -- include for per-area Meaningwave NPC spawning.
// Spawn the named MW guide at its waypoint if not already present anywhere in
// the module. Safe to call from area OnEnter; the tag-existence check prevents
// double-spawning across multiple PC entries.

void MWSpawnAtWaypoint(string sWPTag, string sResRef)
{
    if (GetIsObjectValid(GetObjectByTag(sResRef))) return;
    object oWP = GetWaypointByTag(sWPTag);
    if (!GetIsObjectValid(oWP)) return;
    CreateObject(OBJECT_TYPE_CREATURE, sResRef, GetLocation(oWP));
}
