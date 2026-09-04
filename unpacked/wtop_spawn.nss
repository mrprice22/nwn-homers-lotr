// Weather Top / Amon Sul garrison spawner (roadmap: forbidden-realms-key-tier)
//
// area026 ships empty spawn markers and no creatures at all. This fills them the
// first time a player walks in after a server start:
//
//   12 x tag "wtop_spawn"  -- the summit ring, Z ~15-17. THREE unit types in
//                             rotation, four posts each:
//                               weathertoparc001  Weathertop Archer
//                               weathertopfighte  Weathertop Fighter
//                               wtop_scout        Weathertop Scout
//                             The Scout is imported from the 2009 fork, where
//                             it is a fast Monk/Barbarian/Arcane-Archer skirmisher
//                             (DEX 100) quite unlike this module's own
//                             weathertoparc002 that happens to share its resref
//                             there -- hence the new resref here.
//    4 x tag "wtop_zombie" -- the low ground by the Weather Hills transitions.
//                             wtop_zombie (Barrow-wight of Amon Sul): normal
//                             walk rate, very high HP. Flavour on the approach.
//
// Those four types are also the four sources of the key-shards that open the
// hidden court below -- one ward each, 42% a kill. See wtop_death.nss.
//
// The King and Queen are NOT here. They stand on their thrones in area028
// ("Weather Top's Hidden Court"), behind the wtop_hiddencave trigger, as real
// placed instances -- see wtop_court.nss for why placed rather than spawned.
//
// Called from wtop_enter.nss (area026 OnEnter) after the anti-kiting leash.
//
// Respawn is NOT handled here. Each creature's OnDeath (wtop_death ->
// x2_def_ondeath -> nw_c2_default7 -> SE_DoCreatureRespawn in se_respawn_inc.nss)
// puts it back on the module-standard 900s timer. We therefore fill each post
// exactly once per server run, flagged by the local int WTOP_FILLED on the
// waypoint itself -- without that guard a player re-entering inside the 900s
// window would spawn a second creature and the respawn would then double the
// post up.
//
// Both leash_to_area.nss and SE_DoCreatureRespawn read the creature's "spawn"
// LocalLocation -- the first to send it home if it is kited out of the area, the
// second to decide where it comes back. The blueprints' x2_def_spawn chains
// nw_c2_default9, which already records it, so setting it here is belt and
// braces: it pins the home to the waypoint itself and keeps working if a
// blueprint's OnSpawn is ever changed. Same one-liner as leash_spawn.nss.

const string WTOP_WP_GUARD  = "wtop_spawn";
const string WTOP_WP_ZOMBIE = "wtop_zombie";

const string WTOP_RR_ARCHER  = "weathertoparc001";   // Weathertop Archer,  CR 198
const string WTOP_RR_FIGHTER = "weathertopfighte";   // Weathertop Fighter, CR 199
const string WTOP_RR_SCOUT   = "wtop_scout";         // Weathertop Scout,   CR 249
const string WTOP_RR_ZOMBIE  = "wtop_zombie";        // Barrow-wight of Amon Sul

const string WTOP_FILLED = "WTOP_FILLED";

// Create sResRef at oWP unless that post has already been filled this run.
void WtopFillPost(object oWP, string sResRef)
{
    if (!GetIsObjectValid(oWP)) return;
    if (GetLocalInt(oWP, WTOP_FILLED)) return;

    location lPost = GetLocation(oWP);
    object oCre = CreateObject(OBJECT_TYPE_CREATURE, sResRef, lPost);
    if (!GetIsObjectValid(oCre)) return;        // bad resref -- leave unflagged

    // Home for leash_to_area and for SE_DoCreatureRespawn.
    SetLocalLocation(oCre, "spawn", lPost);

    SetLocalInt(oWP, WTOP_FILLED, TRUE);
}

// Walk every waypoint carrying sTag, dealing the three garrison types round
// robin. GetWaypointByTag only ever returns the first, so use the nth-object
// form (same idiom as q_brn_inc.nss / mw_hall_exit).
void WtopFillGuardPosts()
{
    int n = 0;
    object oWP = GetObjectByTag(WTOP_WP_GUARD, n);

    while (GetIsObjectValid(oWP))
    {
        string sRR;
        switch (n % 3)
        {
            case 0:  sRR = WTOP_RR_ARCHER;  break;
            case 1:  sRR = WTOP_RR_FIGHTER; break;
            default: sRR = WTOP_RR_SCOUT;   break;
        }
        WtopFillPost(oWP, sRR);
        oWP = GetObjectByTag(WTOP_WP_GUARD, ++n);
    }
}

void WtopFillZombiePosts()
{
    int n = 0;
    object oWP = GetObjectByTag(WTOP_WP_ZOMBIE, n);

    while (GetIsObjectValid(oWP))
    {
        WtopFillPost(oWP, WTOP_RR_ZOMBIE);
        oWP = GetObjectByTag(WTOP_WP_ZOMBIE, ++n);
    }
}

void main()
{
    WtopFillGuardPosts();
    WtopFillZombiePosts();
}
