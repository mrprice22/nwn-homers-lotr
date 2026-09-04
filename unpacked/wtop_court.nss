// Weather Top's Hidden Court garrison spawner (roadmap: forbidden-realms-key-tier)
//
// area028 ("Weather Top's Hidden Court") ships 51 empty spawn markers on three
// tags and no creatures at all. This fills them the first time a player walks
// in after a server start:
//
//   23 x "wtop_spawn_epicguard"   -> wtop_crtguard   Royal Guardsman
//   22 x "wtop_spawn_epicarcher"  -> wtop_crtarcher  Royal Archer
//    6 x "wtop_spawn_epicmage"    -> wtop_crtmage    Royal Magus
//
// The King and Queen are deliberately NOT spawned here. They are real PLACED
// instances standing on their thrones, because bin/gen-boss-registry.py only
// sees placed instances and encounter slots -- a script-spawned creature is
// classified "never placed/spawned" and can never reach the Roll of the Fallen.
// The admin's wtop_spawn_king / wtop_spawn_queen waypoints are what gave the
// placements their coordinates; they are left in place as markers.
//
// Same one-fill-per-run structure as wtop_spawn.nss on the hill above, and for
// the same reason: each court member's OnDeath chains SE_DoCreatureRespawn, so
// re-filling a post on every entry would double it up inside the respawn
// window. WTOP_FILLED on the waypoint is the guard.
//
// Called from wtop_c_enter.nss (area028 OnEnter) after the anti-kiting leash.

const string WTOP_C_FILLED = "WTOP_FILLED";

void WtopCourtFillPost(object oWP, string sResRef)
{
    if (!GetIsObjectValid(oWP)) return;
    if (GetLocalInt(oWP, WTOP_C_FILLED)) return;

    location lPost = GetLocation(oWP);
    object oCre = CreateObject(OBJECT_TYPE_CREATURE, sResRef, lPost);
    if (!GetIsObjectValid(oCre)) return;      // bad resref -- leave unflagged

    // Home for leash_to_area and for SE_DoCreatureRespawn; same belt-and-braces
    // pin as wtop_spawn.nss.
    SetLocalLocation(oCre, "spawn", lPost);

    SetLocalInt(oWP, WTOP_C_FILLED, TRUE);
}

// GetWaypointByTag only ever returns the first match, so walk the nth-object
// form (the q_brn_inc / wtop_spawn idiom).
void WtopCourtFillPosts(string sTag, string sResRef)
{
    int n = 0;
    object oWP = GetObjectByTag(sTag, n);

    while (GetIsObjectValid(oWP))
    {
        WtopCourtFillPost(oWP, sResRef);
        oWP = GetObjectByTag(sTag, ++n);
    }
}

void main()
{
    WtopCourtFillPosts("wtop_spawn_epicguard",  "wtop_crtguard");
    WtopCourtFillPosts("wtop_spawn_epicarcher", "wtop_crtarcher");
    WtopCourtFillPosts("wtop_spawn_epicmage",   "wtop_crtmage");
}
