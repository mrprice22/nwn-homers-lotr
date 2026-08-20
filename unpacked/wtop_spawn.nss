// Weather Top / Amon Sul garrison spawner (roadmap: forbidden-realms-key-tier)
//
// area026 ships with 15 empty spawn markers and no creatures at all. This fills
// them the first time a player walks in after a server start:
//
//   11 x tag "wtop_spawn"  -- the summit ring, Z ~15-17. Alternating
//                             weathertoparc001 (Weathertop Archer) and
//                             weathertopfighte (Weathertop Fighter), 6 archers
//                             to 5 fighters. That archer-heavy mix is how the
//                             hill is garrisoned in both forked modules'
//                             "wheathertop" area (11-12 archers to 7-8
//                             fighters), and weathertoparc001 is also the
//                             archer in this module's own weathertop.ute.
//    4 x tag "wtop_zombie" -- the low ground by the Weather Hills transitions.
//                             wtop_zombie (Barrow-wight of Amon Sul): normal
//                             walk rate, very high HP. Flavour on the approach.
//                             (Was creaturespeed.2da row 1 = Immobile, which
//                             froze them on the spot -- row 4 = Normal now.)
//
// The King and Queen are NOT here -- they belong to the royal court area behind
// wtop_hiddencave, which is not built yet.
//
// Called from wtop_enter.nss (area026 OnEnter) after the anti-kiting leash.
//
// Respawn is NOT handled here. Each creature's OnDeath (x2_def_ondeath ->
// nw_c2_default7 -> SE_DoCreatureRespawn in se_respawn_inc.nss) puts it back on
// the module-standard 900s timer. We therefore fill each post exactly once per
// server run, flagged by the local int WTOP_FILLED on the waypoint itself --
// without that guard a player re-entering inside the 900s window would spawn a
// second creature and the respawn would then double the post up.
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
const string WTOP_RR_FIGHTER = "weathertopfighte";   // Weathertop Fighter, CR 100
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

// Walk every waypoint carrying sTag. GetWaypointByTag only ever returns the
// first, so use the nth-object form (same idiom as q_brn_inc.nss / mw_hall_exit).
// nAlternate: when TRUE, even posts get sResRef and odd posts get sResRefAlt.
void WtopFillPosts(string sTag, string sResRef, string sResRefAlt, int nAlternate)
{
    int n = 0;
    object oWP = GetObjectByTag(sTag, n);

    while (GetIsObjectValid(oWP))
    {
        if (nAlternate && (n % 2))
            WtopFillPost(oWP, sResRefAlt);
        else
            WtopFillPost(oWP, sResRef);

        oWP = GetObjectByTag(sTag, ++n);
    }
}

void main()
{
    WtopFillPosts(WTOP_WP_GUARD,  WTOP_RR_ARCHER, WTOP_RR_FIGHTER, TRUE);
    WtopFillPosts(WTOP_WP_ZOMBIE, WTOP_RR_ZOMBIE, "",              FALSE);
}
