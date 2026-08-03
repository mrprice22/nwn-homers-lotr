// q_maz_inc.nss - The Twentieth Plot of Mazarbul shared helpers
// (roadmap: twentieth-plot-mazarbul)
//
// T2 one-off (level 18+), journal tag "mazarbul_20". Frar the Restless - a
// shade of Balin's colony haunting the Chamber of Records - begs the PC to
// finish the colony's last labor: a hidden codicil to the Book of Mazarbul
// names twenty crypt-plots that must be kept sealed. Nineteen hold; the
// twentieth's seal-braziers were never lit. Light the three braziers
// (Chamber of Records + Balin's Tomb), face the wraith that rises to smother
// the third flame, then return to Frar for the Seal of the Twentieth.
//
// Quest state is per-character and persistent (campaign DB MAZ_DB, same
// scheme as Ferny's Return "fret"): "stage" 0 none / 1 accepted / 2 braziers
// done, wraith up / 3 wraith slain / 4 done, plus per-brazier keys
// "seal_1..3" - relog- and restart-safe, no farmable local state. One-off:
// stage 4 never resets.
//
// Everything is script-spawned at admin-placed waypoints (autopilot
// no-coordinate-picking rule) and no-ops gracefully until they exist:
//   AP_mazarbul20_1 - Frar's shade (chamberofrecords)
//   AP_mazarbul20_2 - brazier 1   (chamberofrecords)
//   AP_mazarbul20_3 - brazier 2   (balinstomb)
//   AP_mazarbul20_4 - brazier 3   (balinstomb)
//   AP_mazarbul20_5 - optional wraith arena spot; if absent the wraith
//                     rises at the brazier that completed the seal.
// Spawning runs from the chamberofrecords/balinstomb OnEnter wrappers
// (q_maz_ent1/q_maz_ent2), double-spawn guarded.
//
// Completability guard: at stage 2, using any brazier re-summons the wraith
// if none is alive (someone else killed it, or the PC died and relogged),
// so the fight can always be re-staged.

const string MAZ_DB        = "maz20";           // campaign DB name
const string MAZ_QUEST     = "mazarbul_20";     // journal tag
const string MAZ_GHOST_RES = "q_maz_ghost";
const string MAZ_GHOST_TAG = "maz_ghost";
const string MAZ_WRAITH_RES = "q_maz_wraith";
const string MAZ_WRAITH_TAG = "maz_wraith";
const string MAZ_BRAZ_RES  = "q_maz_braz";
const string MAZ_BRAZ_TAG  = "maz_brazier";
const string MAZ_WP_PREFIX = "AP_mazarbul20_";  // + 1..5 (admin-placed)

const int MAZ_BRAZIERS = 3;
const int MAZ_MIN_LVL  = 18;
const int MAZ_GOLD     = 1200;
const int MAZ_XP       = 2000;

// Persistent quest stage for oPC (0 none / 1 accepted / 2 wraith / 3 slain /
// 4 done).
int MAZ_GetStage(object oPC)
{
    return GetCampaignInt(MAZ_DB, "stage", oPC);
}

void MAZ_SetStage(object oPC, int nStage)
{
    SetCampaignInt(MAZ_DB, "stage", nStage, oPC);
}

// TRUE if oPC has lit brazier nIdx (1..3).
int MAZ_HasSeal(object oPC, int nIdx)
{
    return GetCampaignInt(MAZ_DB, "seal_" + IntToString(nIdx), oPC);
}

void MAZ_SetSeal(object oPC, int nIdx)
{
    SetCampaignInt(MAZ_DB, "seal_" + IntToString(nIdx), 1, oPC);
}

// Braziers oPC has lit (0..3).
int MAZ_CountSeals(object oPC)
{
    int n = 0;
    int i;
    for (i = 1; i <= MAZ_BRAZIERS; i++)
    {
        if (MAZ_HasSeal(oPC, i)) n++;
    }
    return n;
}

// Walk the master chain to the owning PC (summons/companions/henchmen credit
// their master, same rule as the bestiary); OBJECT_INVALID for non-PC kills.
object MAZ_OwningPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    if (GetIsPC(o) && !GetIsDM(o)) return o;
    return OBJECT_INVALID;
}

// TRUE if a living Wraith of the Twentieth Plot stands anywhere.
int MAZ_WraithAlive()
{
    int n = 0;
    object o = GetObjectByTag(MAZ_WRAITH_TAG, n);
    while (GetIsObjectValid(o))
    {
        if (!GetIsDead(o)) return TRUE;
        o = GetObjectByTag(MAZ_WRAITH_TAG, ++n);
    }
    return FALSE;
}

// TRUE if a brazier with local index nIdx already stands anywhere
// (double-spawn guard for MAZ_SpawnAll).
int MAZ_BrazierExists(int nIdx)
{
    int n = 0;
    object o = GetObjectByTag(MAZ_BRAZ_TAG, n);
    while (GetIsObjectValid(o))
    {
        if (GetLocalInt(o, "q_maz_idx") == nIdx) return TRUE;
        o = GetObjectByTag(MAZ_BRAZ_TAG, ++n);
    }
    return FALSE;
}

// Spawn the ghost and all missing braziers at their admin-placed waypoints.
// Graceful no-op for any waypoint not placed yet; never double-spawns.
void MAZ_SpawnAll()
{
    object oWP = GetWaypointByTag(MAZ_WP_PREFIX + "1");
    if (GetIsObjectValid(oWP)
        && !GetIsObjectValid(GetObjectByTag(MAZ_GHOST_TAG)))
        CreateObject(OBJECT_TYPE_CREATURE, MAZ_GHOST_RES, GetLocation(oWP));

    int i;
    for (i = 1; i <= MAZ_BRAZIERS; i++)
    {
        oWP = GetWaypointByTag(MAZ_WP_PREFIX + IntToString(i + 1));
        if (!GetIsObjectValid(oWP)) continue;
        if (MAZ_BrazierExists(i)) continue;
        object oBraz = CreateObject(OBJECT_TYPE_PLACEABLE, MAZ_BRAZ_RES,
                                    GetLocation(oWP));
        SetLocalInt(oBraz, "q_maz_idx", i);
    }
}

// Raise the wraith. Prefers the optional arena waypoint AP_mazarbul20_5;
// falls back to oFallback's own location (the brazier that completed the
// seal - no coordinate picking). Single-spawn guarded.
void MAZ_SpawnWraith(object oFallback)
{
    if (MAZ_WraithAlive()) return;

    location lLoc = GetLocation(oFallback);
    object oWP = GetWaypointByTag(MAZ_WP_PREFIX + "5");
    if (GetIsObjectValid(oWP)) lLoc = GetLocation(oWP);

    object oWraith = CreateObject(OBJECT_TYPE_CREATURE, MAZ_WRAITH_RES, lLoc);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                          EffectVisualEffect(VFX_FNF_SUMMON_UNDEAD),
                          GetLocation(oWraith));
}
