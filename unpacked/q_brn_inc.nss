// q_brn_inc.nss - Beorn's Garden shared helpers (roadmap: beorns-garden)
//
// T2 daily kill-and-gather quest, journal tag "beorn_garden". Grimbeorn the
// Old, Lord of the Beornings (Beorn's homestead, area "beorn" off the Old
// Forest Road), pays a daily bounty for clearing the wargs raiding the
// bee-meadow and harvesting the great hives. Level BRN_MIN_LVL+.
//
// Two legs, both required for the turn-in:
//   * Wargs  - collect BRN_NEED_PELTS warg pelts. Garden wargs
//     (q_brn_warg, tag BeornGardenWarg) are script-spawned in packs of two
//     at each hive when it is harvested - there are no standing warg
//     encounters near the Carrock, so the hives themselves draw the raiders
//     in. Pelts drop from the q_brn_wd OnDeath wrapper (chains
//     nw_c2_default7; bestiary-safe: bst_install stores q_brn_wd as
//     bst_orig_death at spawn and bst_ondeath chains it after recording).
//   * Honey  - harvest BRN_NEED_HONEY hives. Hive placeables (q_brn_hive,
//     tag HoneyHive) are script-spawned at waypoints AP_beornsgarden_1/2/3
//     by q_brn_spawn from the beorn/carrok/carrokgreater OnEnter wrappers
//     (q_brn_ent1/q_brn_ent2); each no-ops gracefully until the admin
//     places the waypoint. Per-PC per-hive per-day gating lives in
//     questcddb calendar keys ("beorn_garden_h1..3") - relog- and
//     restart-safe, no farmable local state.
//
// Active-state is persistent and item-free, same scheme as the Spider Silk
// Harvest: accepting stamps the questcddb key BRN_ACC (calendar-daily), so
// "active today" = accepted-today && !paid-today. Everything resets at UTC
// midnight together.
//
// Completability guard: if a PC has all three hives harvested but still
// lacks pelts (fled, or someone else landed the kills), re-using any
// harvested hive "rattles" it and calls another pack of wargs, so the day
// can always be finished. Warg spawns are capped per-area so hive-clicking
// can't flood the meadow.

#include "quest_cd_inc"

const string BRN_QUEST     = "beorn_garden";      // questcddb key + journal tag
const string BRN_ACC       = "beorn_garden_acc";  // questcddb accepted-today key
const string BRN_HIVE_KEY  = "beorn_garden_h";    // + hive index 1..3
const string BRN_PELT_TAG  = "q_brn_pelt";        // pelt item tag AND resref
const string BRN_WARG_RES  = "q_brn_warg";        // warg blueprint resref
const string BRN_WARG_TAG  = "BeornGardenWarg";
const string BRN_HIVE_RES  = "q_brn_hive";        // hive blueprint resref
const string BRN_HIVE_TAG  = "HoneyHive";
const string BRN_WP_PREFIX = "AP_beornsgarden_"; // + 1..3 (admin-placed)

const int BRN_NEED_PELTS   = 6;
const int BRN_NEED_HONEY   = 3;
const int BRN_HIVES        = 3;
const int BRN_PACK_SIZE    = 2;    // wargs per angered hive
const int BRN_AREA_CAP     = 4;    // max live garden wargs per area
const int BRN_MIN_LVL      = 12;
const int BRN_GOLD_BASE    = 250;  // + Random(201) => 250-450
const int BRN_XP           = 700;

// TRUE while the garden work is active for oPC: accepted today, not yet paid.
int BRN_IsActive(object oPC)
{
    return QCD_IsDoneToday(oPC, BRN_ACC) && !QCD_IsDoneToday(oPC, BRN_QUEST);
}

// Warg pelts in oPC's pack (stack-aware).
int BRN_CountPelts(object oPC)
{
    int n = 0;
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == BRN_PELT_TAG)
            n += GetItemStackSize(oItem);
        oItem = GetNextItemInInventory(oPC);
    }
    return n;
}

// Remove nCount pelts from oPC's pack, stack-aware.
void BRN_TakePelts(object oPC, int nCount)
{
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem) && nCount > 0)
    {
        if (GetTag(oItem) == BRN_PELT_TAG)
        {
            int nStack = GetItemStackSize(oItem);
            if (nStack > nCount)
            {
                SetItemStackSize(oItem, nStack - nCount);
                nCount = 0;
            }
            else
            {
                nCount -= nStack;
                DestroyObject(oItem);
            }
        }
        oItem = GetNextItemInInventory(oPC);
    }
}

// Hives oPC has harvested today (0..3), from the per-hive calendar keys.
int BRN_CountHoney(object oPC)
{
    int n = 0;
    int i;
    for (i = 1; i <= BRN_HIVES; i++)
    {
        if (QCD_IsDoneToday(oPC, BRN_HIVE_KEY + IntToString(i)))
            n++;
    }
    return n;
}

// Walk the master chain to the owning PC (summons/companions/henchmen credit
// their master, same rule as the bestiary); OBJECT_INVALID for non-PC kills.
object BRN_OwningPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    if (GetIsPC(o) && !GetIsDM(o)) return o;
    return OBJECT_INVALID;
}

// TRUE if a hive with local index nIdx already stands anywhere in the module
// (double-spawn guard for q_brn_spawn).
int BRN_HiveExists(int nIdx)
{
    int n = 0;
    object o = GetObjectByTag(BRN_HIVE_TAG, n);
    while (GetIsObjectValid(o))
    {
        if (GetLocalInt(o, "q_brn_idx") == nIdx) return TRUE;
        o = GetObjectByTag(BRN_HIVE_TAG, ++n);
    }
    return FALSE;
}

// Spawn all missing hives at their admin-placed waypoints. Graceful no-op
// for any waypoint not placed yet; never double-spawns.
void BRN_SpawnHives()
{
    int i;
    for (i = 1; i <= BRN_HIVES; i++)
    {
        object oWP = GetWaypointByTag(BRN_WP_PREFIX + IntToString(i));
        if (!GetIsObjectValid(oWP)) continue;
        if (BRN_HiveExists(i)) continue;
        object oHive = CreateObject(OBJECT_TYPE_PLACEABLE, BRN_HIVE_RES,
                                    GetLocation(oWP));
        SetLocalInt(oHive, "q_brn_idx", i);
    }
}

// Spawn a pack of wargs at oHive (its own location - no coordinate picking).
// Capped at BRN_AREA_CAP live garden wargs in the hive's area so repeated
// hive use can't flood the meadow. Returns the number actually spawned.
int BRN_SpawnWargs(object oHive)
{
    object oArea = GetArea(oHive);
    int nAlive = 0;
    int n = 0;
    object o = GetObjectByTag(BRN_WARG_TAG, n);
    while (GetIsObjectValid(o))
    {
        if (GetArea(o) == oArea && !GetIsDead(o)) nAlive++;
        o = GetObjectByTag(BRN_WARG_TAG, ++n);
    }

    int nSpawned = 0;
    while (nSpawned < BRN_PACK_SIZE && nAlive + nSpawned < BRN_AREA_CAP)
    {
        CreateObject(OBJECT_TYPE_CREATURE, BRN_WARG_RES, GetLocation(oHive));
        nSpawned++;
    }
    return nSpawned;
}
