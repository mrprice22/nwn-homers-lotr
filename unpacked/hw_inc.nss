// hw_inc - Harvest of Shadows: the Halloween seasonal event.
//
// WHEN IT RUNS. Purely a real-world date window, no admin lever:
//   ACTIVE  Oct 15 - Oct 31  pumpkins, skeletons, the Pumpkin King, dark lighting
//   CLAIM   Nov  1 - Nov  7  only the Gourd Board stands, so winners can claim
//   OFF     the rest of the year; nothing here does anything
// The date is read from SQLite (strftime), not the game clock - the game
// calendar runs at its own speed and is not what "October" means to a player.
// The leaderboard is keyed on the year, so next October starts clean.
//
// WHAT IS PERSISTENT. Cursed pumpkins (hostile areas) are rows in the campaign
// DB "halloweendb" and are re-planted at module load, so a reboot does not
// clear them - only a player's weapon does. Boss-ring pumpkins are not stored
// by position at all: their spots are derived from the boss's home (generated
// into hw_areas_inc) and only their cleared_at time is stored, so a ring comes
// back 30 minutes after it is smashed, reboot or not. Town pumpkins (peaceful
// areas) are not stored; they rot away after 15 minutes.
//
// THE AURA. Every hostile creature within HW_AURA_RADIUS of a cursed pumpkin
// gets +1 attack per pumpkin, no cap, through the bonus ledger (source
// BPOOL_SRC_PUMPKIN) - never EffectAttackIncrease directly, which would fight
// every other attack bonus in the module (see bonus_pool_inc.nss). The entry is
// re-registered with a short duration on every pass, so walking away from the
// pumpkins, or smashing them, takes it off on its own.
//
// LIGHTING. Changed at runtime, per area, the first time a PC is in it while
// the event is ACTIVE; the original colours are kept on the area and put back
// when the window closes. No area file is edited.
//
// Hooks into the rest of the module are all one-liners that ExecuteScript a
// hw_* script, so nothing else has to include this file:
//   bleeding.nss     (module heartbeat)  -> hw_tick
//   bst_ondeath.nss  (every creature kill credited to a PC) -> hw_ondeath
//   onmoduleload.nss -> hw_modload

#include "hw_areas_inc"
#include "bonus_pool_inc"
#include "nwnx_object"
#include "color"

const string HW_DB = "halloweendb";

const int HW_PHASE_OFF    = 0;
const int HW_PHASE_ACTIVE = 1;
const int HW_PHASE_CLAIM  = 2;

const string HW_START     = "10-15";
const string HW_END       = "10-31";
const string HW_CLAIM_END = "11-07";

// Tags. Every object the event creates wears one, so the end-of-window sweep
// is a tag loop and can never catch anything else.
const string HW_TAG_TOWN   = "hw_pk_t";    // peaceful-area pumpkin, decays
const string HW_TAG_CURSED = "hw_pk_c";    // hostile-area pumpkin, persistent
const string HW_TAG_BOSS   = "hw_pk_b";    // boss-ring pumpkin, respawns
const string HW_TAG_SKEL   = "hw_skel";
const string HW_TAG_KING   = "hw_pking";
const string HW_TAG_BOARD  = "hw_board";

// Tunables.
const int   HW_TRAVEL_CHANCE_TOWN    = 15;    // 1 in N per heartbeat while moving
const int   HW_TRAVEL_CHANCE_HOSTILE = 60;
const int   HW_KILL_CHANCE_PCT       = 15;
const int   HW_AREA_CAP              = 20;    // cursed pumpkins per area
const int   HW_TOWN_CAP              = 8;     // live town pumpkins per area
const float HW_TOWN_DECAY            = 900.0; // 15 minutes
const float HW_AURA_RADIUS           = 10.0;
const float HW_AURA_DURATION         = 18.0;  // > the 12s aura pass
const int   HW_BOSS_RING             = 3;
const int   HW_BOSS_RESPAWN          = 1800;  // 30 minutes
const float HW_KING_RESPAWN          = 3600.0;
const float HW_SKEL_LIFETIME         = 600.0;
const int   HW_TIER3_MIN_GUTS        = 25;

const string HW_KING_AREA = "deadmarshes";

const string HW_TAG_ALLY   = "hw_ally";    // Pumpkin-Born Skeletons fighting for a PC
const string HW_TAG_WARD   = "hw_ward";    // Harvest Moon healing pumpkin
const string HW_TAG_SEED   = "hw_seed";    // decorative Pumpkin Seeds planting
const string HW_TAG_HEARTH = "hw_hearth";  // Harvest Hearth, house trophy
const float  HW_GUTS_RANGE = 30.0;

int    HW_Now();
int    HW_Year();
int    HW_ReadPhase();
int    HW_Phase();
void   HW_InitDb();
location HW_Scatter(location lAt, float fMin, float fMax);
object HW_SpawnPumpkin(location lAt, string sKind, int nBossSlot = -1, string sKey = "");
void   HW_RespawnBossSlot(int nSlot);
void   HW_PlantBossRings();
void   HW_RestoreWild();
void   HW_SpawnSkeletons(location lAt, int nTier, object oKiller, int nCount);
void   HW_RecomputeAura(object oArea, object oPC);
void   HW_DarkenArea(object oArea, float fFade = 4.0);
void   HW_RestoreLighting(object oArea);
void   HW_SpawnKing();
void   HW_SpawnBoard();
void   HW_SweepAll(int bKeepBoard);
void   HW_Begin();
int    HW_AddGuts(object oPC, int nCount);
int    HW_GetGuts(object oPC);
int    HW_Rank(object oPC);
string HW_TopGuts(int nRows);
int    HW_IsSkeleton(object oCre);

// ---------------------------------------------------------------- time

int HW_Now()
{
    sqlquery q = SqlPrepareQueryObject(GetModule(),
        "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

int HW_Year()
{
    sqlquery q = SqlPrepareQueryObject(GetModule(),
        "SELECT CAST(strftime('%Y','now','localtime') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Reads the calendar. Callers on hot paths use HW_Phase(), which is cached.
int HW_ReadPhase()
{
    sqlquery q = SqlPrepareQueryObject(GetModule(),
        "SELECT strftime('%m-%d','now','localtime')");
    if (!SqlStep(q)) return HW_PHASE_OFF;
    string sMd = SqlGetString(q, 0);
    // "MM-DD" compares correctly as a string.
    q = SqlPrepareQueryObject(GetModule(),
        "SELECT CASE WHEN @d BETWEEN @s AND @e THEN 1 " +
        "WHEN @d > @e AND @d <= @c THEN 2 ELSE 0 END");
    SqlBindString(q, "@d", sMd);
    SqlBindString(q, "@s", HW_START);
    SqlBindString(q, "@e", HW_END);
    SqlBindString(q, "@c", HW_CLAIM_END);
    return SqlStep(q) ? SqlGetInt(q, 0) : HW_PHASE_OFF;
}

// The phase as last read by hw_modload / hw_tick (re-read about once a minute).
int HW_Phase()
{
    return GetLocalInt(GetModule(), "hw_phase");
}

// ---------------------------------------------------------------- db

// Called once from hw_modload (module load) - never on the login frame.
// Table names avoid the reserved meta/db/migrations.
void HW_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "CREATE TABLE IF NOT EXISTS hw_pumpkin (" +
        "pkey TEXT PRIMARY KEY," +
        "area TEXT NOT NULL," +
        "x REAL, y REAL, z REAL, f REAL," +
        "year INTEGER NOT NULL)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(HW_DB,
        "CREATE TABLE IF NOT EXISTS hw_bossring (" +
        "slot INTEGER PRIMARY KEY," +
        "cleared_at INTEGER NOT NULL DEFAULT 0)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(HW_DB,
        "CREATE TABLE IF NOT EXISTS hw_guts (" +
        "year INTEGER NOT NULL," +
        "ident TEXT NOT NULL," +
        "pc_name TEXT," +
        "cdkey TEXT," +
        "count INTEGER NOT NULL DEFAULT 0," +
        "claimed INTEGER NOT NULL DEFAULT 0," +
        "PRIMARY KEY (year, ident))");
    SqlStep(q);

    // Seeds column, added after the table shipped: CREATE TABLE IF NOT EXISTS
    // never alters an existing table, so the column needs its own guarded ALTER.
    q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT COUNT(*) FROM pragma_table_info('hw_guts') WHERE name='seeds'");
    if (SqlStep(q) && SqlGetInt(q, 0) == 0)
    {
        q = SqlPrepareQueryCampaign(HW_DB,
            "ALTER TABLE hw_guts ADD COLUMN seeds INTEGER NOT NULL DEFAULT 0");
        SqlStep(q);
    }

    // Prize power cooldowns: per CHARACTER and power, never per item, so
    // handing the item to a friend does not hand over fresh uses.
    q = SqlPrepareQueryCampaign(HW_DB,
        "CREATE TABLE IF NOT EXISTS hw_cooldown (" +
        "ident TEXT NOT NULL," +
        "power TEXT NOT NULL," +
        "window_start INTEGER NOT NULL DEFAULT 0," +
        "uses INTEGER NOT NULL DEFAULT 0," +
        "PRIMARY KEY (ident, power))");
    SqlStep(q);

    // Harvest Hearths placed in player houses. Restored at every module load,
    // event or not - a trophy is for keeps.
    q = SqlPrepareQueryCampaign(HW_DB,
        "CREATE TABLE IF NOT EXISTS hw_hearth (" +
        "hkey TEXT PRIMARY KEY," +
        "area_tag TEXT NOT NULL," +
        "x REAL, y REAL, z REAL, f REAL," +
        "cdkey TEXT, pc_name TEXT, year INTEGER)");
    SqlStep(q);
}

string HW_Ident(object oPC)
{
    string sUuid = GetObjectUUID(oPC);
    if (sUuid != "") return sUuid;
    return "k:" + GetPCPublicCDKey(oPC) + "|" + GetName(oPC);
}

// Add to this character's turned-in total for this year; returns the new total.
int HW_AddGuts(object oPC, int nCount)
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "INSERT INTO hw_guts (year, ident, pc_name, cdkey, count) " +
        "VALUES (@y, @i, @n, @k, @c) " +
        "ON CONFLICT(year, ident) DO UPDATE SET count = count + @c, pc_name = @n");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindString(q, "@i", HW_Ident(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindInt(q, "@c", nCount);
    SqlStep(q);
    return HW_GetGuts(oPC);
}

int HW_GetGuts(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT count FROM hw_guts WHERE year=@y AND ident=@i");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindString(q, "@i", HW_Ident(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// 1-based rank among this year's collectors, 0 when the PC has none. Ties are
// broken by who got there first (rowid), the same order the board lists.
int HW_Rank(object oPC)
{
    int nMine = HW_GetGuts(oPC);
    if (nMine <= 0) return 0;
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT COUNT(*) FROM hw_guts WHERE year=@y AND " +
        "(count > @c OR (count = @c AND rowid < " +
        "(SELECT rowid FROM hw_guts WHERE year=@y AND ident=@i)))");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindInt(q, "@c", nMine);
    SqlBindString(q, "@i", HW_Ident(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) + 1 : 0;
}

string HW_TopGuts(int nRows)
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT pc_name, count FROM hw_guts WHERE year=@y AND count > 0 " +
        "ORDER BY count DESC, rowid ASC LIMIT @l");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindInt(q, "@l", nRows);
    string sOut = "";
    int nRank = 0;
    while (SqlStep(q))
    {
        nRank++;
        sOut += IntToString(nRank) + ". " + SqlGetString(q, 0)
              + " -- " + IntToString(SqlGetInt(q, 1)) + "\n";
    }
    return sOut;
}

// ---------------------------------------------------------------- helpers

// Tier -> the level a fight there is pitched at (module CRs are inflated, so
// this is the ladder the skeletons and pumpkins scale on, not the CR).
int HW_TierLevel(int nTier)
{
    if (nTier <= 0) return 1;
    return nTier * 10 - 2;   // 8, 18, 28, 38, 48, 58
}

int HW_IsSkeleton(object oCre)
{
    if (GetTag(oCre) == HW_TAG_SKEL) return TRUE;
    if (FindSubString(GetStringLowerCase(GetName(oCre)), "skelet") >= 0) return TRUE;
    // appearance.2da rows labelled "Skeleton" (stock + CEP).
    string sApp = "|" + IntToString(GetAppearanceType(oCre)) + "|";
    return FindSubString("|36|62|63|70|71|148|150|182|1049|1277|1285|1286|1287|"
        + "1288|1289|1309|1310|1440|1441|1442|1445|1446|1447|1451|1579|1580|"
        + "1581|1769|3068|3069|3070|3071|3290|3291|3292|3293|3294|3295|3296|"
        + "3894|3901|3902|3903|6445|6752|6937|", sApp) >= 0;
}

int HW_Walkable(location l)
{
    int nMat = GetSurfaceMaterial(l);
    if (nMat <= 0) return FALSE;
    return Get2DAString("surfacemat", "Walk", nMat) == "1";
}

// A walkable spot fMin..fMax metres from lAt; lAt itself if eight tries miss.
location HW_Scatter(location lAt, float fMin, float fMax)
{
    object oArea = GetAreaFromLocation(lAt);
    vector v = GetPositionFromLocation(lAt);
    int i;
    for (i = 0; i < 8; i++)
    {
        float fAng = IntToFloat(Random(360));
        float fDist = fMin + IntToFloat(Random(FloatToInt((fMax - fMin) * 10.0) + 1)) / 10.0;
        vector p = Vector(v.x + fDist * cos(fAng), v.y + fDist * sin(fAng), v.z);
        location l = Location(oArea, p, IntToFloat(Random(360)));
        if (HW_Walkable(l))
        {
            // Snap to the walkmesh height.
            p.z = GetGroundHeight(l);
            return Location(oArea, p, IntToFloat(Random(360)));
        }
    }
    return lAt;
}

// Area by resref. The first call indexes every area onto module locals, so
// re-planting a few thousand stored pumpkins is not a few thousand area walks.
object HW_AreaByResRef(string sArea)
{
    object oMod = GetModule();
    if (!GetLocalInt(oMod, "hw_area_idx"))
    {
        object oA = GetFirstArea();
        while (GetIsObjectValid(oA))
        {
            SetLocalObject(oMod, "hw_area_" + GetResRef(oA), oA);
            oA = GetNextArea();
        }
        SetLocalInt(oMod, "hw_area_idx", 1);
    }
    return GetLocalObject(oMod, "hw_area_" + sArea);
}

int HW_CursedCount(string sArea)
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT COUNT(*) FROM hw_pumpkin WHERE area=@a");
    SqlBindString(q, "@a", sArea);
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// ---------------------------------------------------------------- pumpkins

// Apply the tier's toughness and the glow. Town pumpkins are a soft decoy.
void HW_DressPumpkin(object oPk, int nTier)
{
    effect eLight = SupernaturalEffect(EffectVisualEffect(VFX_DUR_LIGHT_ORANGE_10));
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eLight, oPk);
    int nHp = (nTier <= 0) ? 30 : 60 * nTier * nTier + 40;   // 100 .. 2200
    NWNX_Object_SetMaxHitPoints(oPk, nHp);
    NWNX_Object_SetCurrentHitPoints(oPk, nHp);
    SetHardness(nTier * 3, oPk);                              // 0 .. 18
    if (nTier > 0)
        ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            SupernaturalEffect(EffectACIncrease(nTier * 2)), oPk);
    SetLocalInt(oPk, "hw_tier", nTier);
}

// A town pumpkin leaving the world, by rot or by a weapon: free its slot.
void HW_TownGone(object oArea)
{
    int n = GetLocalInt(oArea, "hw_town_n") - 1;
    SetLocalInt(oArea, "hw_town_n", n < 0 ? 0 : n);
}

void HW_TownRot(object oPk)
{
    if (!GetIsObjectValid(oPk)) return;   // smashed first; hw_pk_death freed it
    HW_TownGone(GetArea(oPk));
    DestroyObject(oPk);
}

// sKind: "town" / "cursed" / "boss". lAt is used exactly - callers scatter.
// sKey (cursed only): an existing DB row being re-planted; "" mints a new row.
object HW_SpawnPumpkin(location lAt, string sKind, int nBossSlot = -1, string sKey = "")
{
    object oArea = GetAreaFromLocation(lAt);
    string sArea = GetResRef(oArea);
    if (!GetIsObjectValid(oArea) || HW_AreaExcluded(sArea)) return OBJECT_INVALID;
    int nTier = HW_AreaTier(sArea);

    string sTag = HW_TAG_CURSED;
    if (sKind == "town")
    {
        sTag = HW_TAG_TOWN;
        if (GetLocalInt(oArea, "hw_town_n") >= HW_TOWN_CAP) return OBJECT_INVALID;
        nTier = 0;
    }
    else if (sKind == "boss")
    {
        sTag = HW_TAG_BOSS;
        if (nTier <= 0) nTier = 3;   // a boss in a "peaceful" hub still bites
    }
    else if (sKey == "" && HW_CursedCount(sArea) >= HW_AREA_CAP)
        return OBJECT_INVALID;

    string sRes = "hw_pumpkin" + IntToString(1 + Random(4));
    object oPk = CreateObject(OBJECT_TYPE_PLACEABLE, sRes, lAt, FALSE, sTag);
    if (!GetIsObjectValid(oPk)) return OBJECT_INVALID;
    HW_DressPumpkin(oPk, nTier);
    SetLocalString(oPk, "hw_kind", sKind);
    if (sKind == "cursed")    SetName(oPk, "Cursed Jack-o'-Lantern");
    else if (sKind == "boss") SetName(oPk, "Gravewatch Pumpkin");

    if (sKind == "town")
    {
        SetLocalInt(oArea, "hw_town_n", GetLocalInt(oArea, "hw_town_n") + 1);
        AssignCommand(GetModule(), DelayCommand(HW_TOWN_DECAY, HW_TownRot(oPk)));
    }
    else if (sKind == "boss")
    {
        SetLocalInt(oPk, "hw_slot", nBossSlot);
    }
    else
    {
        if (sKey == "")
        {
            sKey = IntToString(HW_Now()) + "_" + IntToString(Random(1000000));
            vector v = GetPositionFromLocation(lAt);
            sqlquery q = SqlPrepareQueryCampaign(HW_DB,
                "INSERT OR REPLACE INTO hw_pumpkin (pkey, area, x, y, z, f, year) " +
                "VALUES (@k, @a, @x, @y, @z, @f, @yr)");
            SqlBindString(q, "@k", sKey);
            SqlBindString(q, "@a", sArea);
            SqlBindFloat(q, "@x", v.x);
            SqlBindFloat(q, "@y", v.y);
            SqlBindFloat(q, "@z", v.z);
            SqlBindFloat(q, "@f", GetFacingFromLocation(lAt));
            SqlBindInt(q, "@yr", HW_Year());
            SqlStep(q);
        }
        SetLocalString(oPk, "hw_key", sKey);
    }
    return oPk;
}

// Re-plant every stored cursed pumpkin (module load).
void HW_RestoreWild()
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT pkey, area, x, y, z, f FROM hw_pumpkin");
    while (SqlStep(q))
    {
        object oArea = HW_AreaByResRef(SqlGetString(q, 1));
        if (!GetIsObjectValid(oArea)) continue;
        location l = Location(oArea,
            Vector(SqlGetFloat(q, 2), SqlGetFloat(q, 3), SqlGetFloat(q, 4)),
            SqlGetFloat(q, 5));
        HW_SpawnPumpkin(l, "cursed", -1, SqlGetString(q, 0));
    }
}

// Boss ring slot nSlot = boss index * HW_BOSS_RING + k. Position is fixed:
// k-th point on an 8m circle around the boss's home.
location HW_BossSlotLocation(int nSlot)
{
    string s = HW_BossHome(nSlot / HW_BOSS_RING);
    if (s == "") return GetStartingLocation();
    // "resref|area|x|y|z"
    int a = FindSubString(s, "|");
    int b = FindSubString(s, "|", a + 1);
    int c = FindSubString(s, "|", b + 1);
    int d = FindSubString(s, "|", c + 1);
    object oArea = HW_AreaByResRef(GetSubString(s, a + 1, b - a - 1));
    float x = StringToFloat(GetSubString(s, b + 1, c - b - 1));
    float y = StringToFloat(GetSubString(s, c + 1, d - c - 1));
    float z = StringToFloat(GetSubString(s, d + 1, 32));
    float fAng = IntToFloat((nSlot % HW_BOSS_RING) * (360 / HW_BOSS_RING));
    location l = Location(oArea, Vector(x + 8.0 * cos(fAng), y + 8.0 * sin(fAng), z), fAng);
    if (!HW_Walkable(l)) l = HW_Scatter(Location(oArea, Vector(x, y, z), 0.0), 5.0, 10.0);
    return l;
}

void HW_RespawnBossSlot(int nSlot)
{
    if (HW_Phase() != HW_PHASE_ACTIVE) return;
    // Already standing (a duplicate timer, or the module-load pass got there).
    int n = 0;
    object o = GetObjectByTag(HW_TAG_BOSS, n);
    while (GetIsObjectValid(o))
    {
        if (GetLocalInt(o, "hw_slot") == nSlot) return;
        n++;
        o = GetObjectByTag(HW_TAG_BOSS, n);
    }
    location l = HW_BossSlotLocation(nSlot);
    if (GetIsObjectValid(GetAreaFromLocation(l)))
        HW_SpawnPumpkin(l, "boss", nSlot);
}

// Plant every boss ring slot that is not on a respawn cooldown, and schedule
// the rest for when they come due. Module load (and the Oct 15 rollover) only.
void HW_PlantBossRings()
{
    int nNow = HW_Now();
    int nSlots = HW_BOSS_HOME_COUNT * HW_BOSS_RING;
    int i;
    for (i = 0; i < nSlots; i++)
    {
        sqlquery q = SqlPrepareQueryCampaign(HW_DB,
            "SELECT cleared_at FROM hw_bossring WHERE slot=@s");
        SqlBindInt(q, "@s", i);
        int nLeft = 0;
        if (SqlStep(q)) nLeft = SqlGetInt(q, 0) + HW_BOSS_RESPAWN - nNow;
        if (nLeft > 0)
            DelayCommand(IntToFloat(nLeft), HW_RespawnBossSlot(i));
        else
            HW_RespawnBossSlot(i);
    }
}

// ---------------------------------------------------------------- skeletons

void HW_SpawnSkeletons(location lAt, int nTier, object oKiller, int nCount)
{
    int nLevel = HW_TierLevel(nTier);
    if (GetIsObjectValid(oKiller) && GetHitDice(oKiller) > nLevel)
        nLevel = GetHitDice(oKiller);

    string sRes = "hw_skel_4";
    if (nLevel <= 15)      sRes = "hw_skel_1";
    else if (nLevel <= 30) sRes = "hw_skel_2";
    else if (nLevel <= 45) sRes = "hw_skel_3";

    int i;
    for (i = 0; i < nCount; i++)
    {
        location l = HW_Scatter(lAt, 1.0, 3.0);
        object oSk = CreateObject(OBJECT_TYPE_CREATURE, sRes, l, FALSE, HW_TAG_SKEL);
        if (!GetIsObjectValid(oSk)) continue;
        SetLocalInt(oSk, "SE_NO_RESPAWN", 1);
        // Within the band, scale to the level: more HP and a little AC.
        effect e = EffectLinkEffects(EffectTemporaryHitpoints(nLevel * 20),
                                     EffectACIncrease(nLevel / 5));
        ApplyEffectToObject(DURATION_TYPE_PERMANENT, SupernaturalEffect(e), oSk);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_SUMMON_UNDEAD), oSk);
        DestroyObject(oSk, HW_SKEL_LIFETIME);
        if (GetIsObjectValid(oKiller))
            AssignCommand(oSk, ActionAttack(oKiller));
    }
}

// ---------------------------------------------------------------- aura

void HW_AuraNear(object oPk, object oPC)
{
    location l = GetLocation(oPk);
    object o = GetFirstObjectInShape(SHAPE_SPHERE, HW_AURA_RADIUS, l, FALSE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        if (!GetIsPC(o) && !GetIsDead(o) && GetIsReactionTypeHostile(oPC, o)
            && !GetIsPC(GetMaster(o)))
        {
            int n = GetLocalInt(o, "hw_aura_n");
            if (n == 0)
            {
                // Remember who to render once the count is complete.
                int nList = GetLocalInt(GetModule(), "hw_aura_cnt");
                SetLocalObject(GetModule(), "hw_aura_" + IntToString(nList), o);
                SetLocalInt(GetModule(), "hw_aura_cnt", nList + 1);
            }
            SetLocalInt(o, "hw_aura_n", n + 1);
        }
        o = GetNextObjectInShape(SHAPE_SPHERE, HW_AURA_RADIUS, l, FALSE, OBJECT_TYPE_CREATURE);
    }
}

// One pass for an area with a PC in it: count the cursed and boss pumpkins
// near each hostile creature, then register the total in the ledger.
void HW_RecomputeAura(object oArea, object oPC)
{
    object oMod = GetModule();
    SetLocalInt(oMod, "hw_aura_cnt", 0);

    int n = 1;
    object oPk = GetNearestObjectByTag(HW_TAG_CURSED, oPC, n);
    while (GetIsObjectValid(oPk))
    {
        HW_AuraNear(oPk, oPC);
        n++;
        oPk = GetNearestObjectByTag(HW_TAG_CURSED, oPC, n);
    }
    n = 1;
    oPk = GetNearestObjectByTag(HW_TAG_BOSS, oPC, n);
    while (GetIsObjectValid(oPk))
    {
        HW_AuraNear(oPk, oPC);
        n++;
        oPk = GetNearestObjectByTag(HW_TAG_BOSS, oPC, n);
    }

    int nList = GetLocalInt(oMod, "hw_aura_cnt");
    int i;
    for (i = 0; i < nList; i++)
    {
        object o = GetLocalObject(oMod, "hw_aura_" + IntToString(i));
        DeleteLocalObject(oMod, "hw_aura_" + IntToString(i));
        if (!GetIsObjectValid(o)) continue;
        BPool_Set(o, BPOOL_CH_ATTACK, BPOOL_SRC_PUMPKIN,
                  GetLocalInt(o, "hw_aura_n"), HW_AURA_DURATION);
        DeleteLocalInt(o, "hw_aura_n");
    }
    DeleteLocalInt(oMod, "hw_aura_cnt");
}

// ---------------------------------------------------------------- lighting

int HW_Shade(int nColor, float fR, float fG, float fB)
{
    int r = FloatToInt(IntToFloat((nColor >> 16) & 0xFF) * fR);
    int g = FloatToInt(IntToFloat((nColor >> 8) & 0xFF) * fG);
    int b = FloatToInt(IntToFloat(nColor & 0xFF) * fB);
    if (r > 255) r = 255;
    if (g > 255) g = 255;
    if (b > 255) b = 255;
    return (r << 16) | (g << 8) | b;
}

void HW_DarkenArea(object oArea, float fFade = 4.0)
{
    if (GetLocalInt(oArea, "hw_lit")) return;
    if (HW_AreaExcluded(GetResRef(oArea))) return;
    SetLocalInt(oArea, "hw_lit", 1);

    int bInside = GetIsAreaInterior(oArea);
    // Ambient goes dim and violet, diffuse dim and pumpkin-orange.
    float fA = bInside ? 0.75 : 0.55;
    int i;
    for (i = AREA_LIGHT_COLOR_MOON_AMBIENT; i <= AREA_LIGHT_COLOR_SUN_DIFFUSE; i++)
    {
        int c = GetAreaLightColor(i, oArea);
        SetLocalInt(oArea, "hw_light_" + IntToString(i), c);
        int bAmbient = (i == AREA_LIGHT_COLOR_MOON_AMBIENT || i == AREA_LIGHT_COLOR_SUN_AMBIENT);
        int n = bAmbient ? HW_Shade(c, fA, fA * 0.8, fA * 1.1)
                         : HW_Shade(c, fA * 1.15, fA * 0.85, fA * 0.6);
        SetAreaLightColor(i, n, oArea, fFade);
    }

    SetLocalInt(oArea, "hw_fogc_s", GetFogColor(FOG_TYPE_SUN, oArea));
    SetLocalInt(oArea, "hw_fogc_m", GetFogColor(FOG_TYPE_MOON, oArea));
    SetLocalInt(oArea, "hw_foga_s", GetFogAmount(FOG_TYPE_SUN, oArea));
    SetLocalInt(oArea, "hw_foga_m", GetFogAmount(FOG_TYPE_MOON, oArea));
    SetFogColor(FOG_TYPE_SUN, 0x3A2818, oArea, fFade);    // smoky ember
    SetFogColor(FOG_TYPE_MOON, 0x24142E, oArea, fFade);   // bruise violet
    int nMin = bInside ? 8 : 18;
    if (GetFogAmount(FOG_TYPE_SUN, oArea) < nMin) SetFogAmount(FOG_TYPE_SUN, nMin, oArea);
    if (GetFogAmount(FOG_TYPE_MOON, oArea) < nMin) SetFogAmount(FOG_TYPE_MOON, nMin, oArea);
}

void HW_RestoreLighting(object oArea)
{
    if (!GetLocalInt(oArea, "hw_lit")) return;
    int i;
    for (i = AREA_LIGHT_COLOR_MOON_AMBIENT; i <= AREA_LIGHT_COLOR_SUN_DIFFUSE; i++)
        SetAreaLightColor(i, GetLocalInt(oArea, "hw_light_" + IntToString(i)), oArea, 4.0);
    SetFogColor(FOG_TYPE_SUN, GetLocalInt(oArea, "hw_fogc_s"), oArea, 4.0);
    SetFogColor(FOG_TYPE_MOON, GetLocalInt(oArea, "hw_fogc_m"), oArea, 4.0);
    SetFogAmount(FOG_TYPE_SUN, GetLocalInt(oArea, "hw_foga_s"), oArea);
    SetFogAmount(FOG_TYPE_MOON, GetLocalInt(oArea, "hw_foga_m"), oArea);
    DeleteLocalInt(oArea, "hw_lit");
}

// ---------------------------------------------------------------- king, board

// Somewhere the King can stand: a random placeable in the marsh, scattered
// onto walkable ground beside it.
location HW_RandomMarshSpot(object oArea)
{
    int nCount = 0;
    object o = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(o))
    {
        if (GetObjectType(o) == OBJECT_TYPE_PLACEABLE) nCount++;
        o = GetNextObjectInArea(oArea);
    }
    int nPick = (nCount > 0) ? Random(nCount) : 0;
    o = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(o))
    {
        if (GetObjectType(o) == OBJECT_TYPE_PLACEABLE)
        {
            // Not beside a door: the corpses ringing the mausoleum door
            // (Portdeadmarsh) put the King inside the building's footprint.
            object oDoor = GetNearestObject(OBJECT_TYPE_DOOR, o);
            int bNearDoor = GetIsObjectValid(oDoor) && GetDistanceBetween(o, oDoor) < 15.0;
            if (nPick <= 0 && !bNearDoor) return HW_Scatter(GetLocation(o), 2.0, 6.0);
            nPick--;
        }
        o = GetNextObjectInArea(oArea);
    }
    vector vMid = Vector(IntToFloat(GetAreaSize(AREA_WIDTH, oArea)) * 5.0,
                         IntToFloat(GetAreaSize(AREA_HEIGHT, oArea)) * 5.0, 0.0);
    return Location(oArea, vMid, 0.0);
}

void HW_SpawnKing()
{
    if (HW_Phase() != HW_PHASE_ACTIVE) return;
    if (GetIsObjectValid(GetObjectByTag(HW_TAG_KING))) return;
    object oArea = HW_AreaByResRef(HW_KING_AREA);
    if (!GetIsObjectValid(oArea)) return;
    object oKing = CreateObject(OBJECT_TYPE_CREATURE, "hw_pking",
                                HW_RandomMarshSpot(oArea), FALSE, HW_TAG_KING);
    SetLocalInt(oKing, "SE_NO_RESPAWN", 1);
    SetObjectVisualTransform(oKing, OBJECT_VISUAL_TRANSFORM_SCALE, 1.4);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(EffectVisualEffect(VFX_DUR_GLOW_LIGHT_ORANGE)), oKing);
}

// The Gourd Board stands beside the Crash Party board's spot in the Well of Eru.
void HW_SpawnBoard()
{
    if (GetIsObjectValid(GetObjectByTag(HW_TAG_BOARD))) return;
    object oWp = GetWaypointByTag("cp_board_wp");
    if (!GetIsObjectValid(oWp)) return;
    location lWp = GetLocation(oWp);
    vector v = GetPositionFromLocation(lWp);
    float f = GetFacingFromLocation(lWp);
    // Three metres to the board's right.
    location l = Location(GetArea(oWp),
        Vector(v.x + 3.0 * cos(f - 90.0), v.y + 3.0 * sin(f - 90.0), v.z), f);
    CreateObject(OBJECT_TYPE_PLACEABLE, "hw_board", l, FALSE, HW_TAG_BOARD);
}

void HW_DestroyTag(string sTag)
{
    int n = 0;
    object o = GetObjectByTag(sTag, n);
    while (GetIsObjectValid(o))
    {
        DestroyObject(o);
        n++;
        o = GetObjectByTag(sTag, n);
    }
}

// The window closed. Stored cursed pumpkins stay in the DB untouched (the
// next October wipes them, see hw_modload) - only the world is cleared.
void HW_SweepAll(int bKeepBoard)
{
    HW_DestroyTag(HW_TAG_TOWN);
    HW_DestroyTag(HW_TAG_CURSED);
    HW_DestroyTag(HW_TAG_BOSS);
    HW_DestroyTag(HW_TAG_SKEL);
    HW_DestroyTag(HW_TAG_KING);
    if (!bKeepBoard) HW_DestroyTag(HW_TAG_BOARD);
    object oArea = GetFirstArea();
    while (GetIsObjectValid(oArea))
    {
        HW_RestoreLighting(oArea);
        DeleteLocalInt(oArea, "hw_town_n");
        oArea = GetNextArea();
    }
}

// The window opened (module load inside it, or the Oct 15 rollover on a
// running server). A new year wipes last October's leftovers first.
void HW_Begin()
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "DELETE FROM hw_pumpkin WHERE year <> @y");
    SqlBindInt(q, "@y", HW_Year());
    SqlStep(q);
    // Darken every area now, not on a PC's first visit: the server holds the
    // area's light values and hands them to each client as it loads the area,
    // so there is no fade-in after the loading screen.
    object oA = GetFirstArea();
    while (GetIsObjectValid(oA))
    {
        HW_DarkenArea(oA, 0.0);
        oA = GetNextArea();
    }
    HW_RestoreWild();
    HW_PlantBossRings();
    HW_SpawnKing();
    HW_SpawnBoard();
}

// A spooky noise from one pumpkin near the PC now and then. Driven from the
// module heartbeat rather than a heartbeat on every pumpkin: a few thousand
// placeable heartbeats is real load on this box, a nearest-object lookup per
// PC is not.
void HW_Spook(object oPC)
{
    if (Random(4) != 0) return;
    object oPk = GetNearestObjectByTag(HW_TAG_CURSED, oPC);
    if (!GetIsObjectValid(oPk) || GetDistanceBetween(oPk, oPC) > 25.0)
        oPk = GetNearestObjectByTag(HW_TAG_TOWN, oPC);
    if (!GetIsObjectValid(oPk) || GetDistanceBetween(oPk, oPC) > 25.0)
        oPk = GetNearestObjectByTag(HW_TAG_BOSS, oPC);
    if (!GetIsObjectValid(oPk) || GetDistanceBetween(oPk, oPC) > 25.0) return;

    string sSnd;
    switch (Random(10))
    {
        case 0: sSnd = "as_pl_lafspook1"; break;
        case 1: sSnd = "as_pl_lafspook2"; break;
        case 2: sSnd = "as_pl_lafspook3"; break;
        case 3: sSnd = "as_hr_x2ghost1"; break;
        case 4: sSnd = "as_hr_x2ghost4"; break;
        case 5: sSnd = "as_pl_wailingm1"; break;
        case 6: sSnd = "as_pl_wailingm3"; break;
        case 7: sSnd = "as_an_owlhoot1"; break;
        case 8: sSnd = "as_an_crow1"; break;
        default: sSnd = "as_hr_x2chnratl1"; break;
    }
    AssignCommand(oPk, PlaySound(sSnd));
}


// ---------------------------------------------------------------- guts, no clicking

// Put nCount guts straight into the pack of oKiller and every party member in
// the same area within HW_GUTS_RANGE of lAt. Everyone gets the full amount -
// grouping is rewarded, not split. No PC known: the nearest PC in range gets
// them. Nothing is ever dropped on the ground.
void HW_GiveGuts(object oKiller, location lAt, int nCount)
{
    object oArea = GetAreaFromLocation(lAt);
    if (!GetIsObjectValid(oKiller) || !GetIsPC(oKiller))
    {
        oKiller = GetNearestCreatureToLocation(CREATURE_TYPE_PLAYER_CHAR, PLAYER_CHAR_IS_PC, lAt);
        if (!GetIsObjectValid(oKiller) || GetArea(oKiller) != oArea
            || GetDistanceBetweenLocations(GetLocation(oKiller), lAt) > HW_GUTS_RANGE)
            return;
    }
    object oPC = GetFirstFactionMember(oKiller, TRUE);
    while (GetIsObjectValid(oPC))
    {
        if (!GetIsDM(oPC) && GetArea(oPC) == oArea
            && GetDistanceBetweenLocations(GetLocation(oPC), lAt) <= HW_GUTS_RANGE)
        {
            CreateItemOnObject("hw_guts", oPC, nCount);
            FloatingTextStringOnCreature("+" + IntToString(nCount) + " Pumpkin Guts", oPC, FALSE);
        }
        oPC = GetNextFactionMember(oKiller, TRUE);
    }
}

// ---------------------------------------------------------------- prize power cooldowns

string HW_MinText(int nSecs)
{
    int nMin = (nSecs + 59) / 60;
    return IntToString(nMin) + (nMin == 1 ? " minute" : " minutes");
}

// N uses per nWindow real seconds (default 90 min = one "day" on this server,
// where free instant resting would refill a stock N/day on every rest). The
// window opens on the first use; all N come back when it ends. Survives rest,
// relog and reboot. Returns TRUE and spends a use, or FALSE and says how long.
int HW_TryUse(object oPC, string sPower, string sName, int nPerWindow, int nWindow = 5400)
{
    string sId = HW_Ident(oPC);
    int nNow = HW_Now();
    int nStart = 0;
    int nUses = 0;
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT window_start, uses FROM hw_cooldown WHERE ident=@i AND power=@p");
    SqlBindString(q, "@i", sId);
    SqlBindString(q, "@p", sPower);
    if (SqlStep(q)) { nStart = SqlGetInt(q, 0); nUses = SqlGetInt(q, 1); }

    if (nNow - nStart >= nWindow) { nStart = nNow; nUses = 0; }
    if (nUses >= nPerWindow)
    {
        SendMessageToPC(oPC, COLOR_ORANGE + sName + " recovers in "
            + HW_MinText(nStart + nWindow - nNow) + "." + COLOR_END);
        return FALSE;
    }
    nUses++;
    q = SqlPrepareQueryCampaign(HW_DB,
        "INSERT INTO hw_cooldown (ident, power, window_start, uses) VALUES (@i, @p, @s, @u) " +
        "ON CONFLICT(ident, power) DO UPDATE SET window_start=@s, uses=@u");
    SqlBindString(q, "@i", sId);
    SqlBindString(q, "@p", sPower);
    SqlBindInt(q, "@s", nStart);
    SqlBindInt(q, "@u", nUses);
    SqlStep(q);
    SendMessageToPC(oPC, COLOR_ORANGE + sName + ": " + IntToString(nPerWindow - nUses)
        + " of " + IntToString(nPerWindow) + " uses left; all return "
        + HW_MinText(nStart + nWindow - nNow) + " from now." + COLOR_END);
    return TRUE;
}

// ---------------------------------------------------------------- allies, healing pumpkins

// Pumpkin-Born Skeletons fighting FOR oPC (Lantern, Scythe). Defender faction:
// friendly to players, hostile to the Hostile faction. Not summons, so they
// never take the summon slot; they crumble after fLife.
void HW_SpawnAllySkeletons(object oPC, location lAt, int nCount, float fLife)
{
    int nLevel = GetHitDice(oPC);
    string sRes = "hw_skel_4";
    if (nLevel <= 15)      sRes = "hw_skel_1";
    else if (nLevel <= 30) sRes = "hw_skel_2";
    else if (nLevel <= 45) sRes = "hw_skel_3";
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oSk = CreateObject(OBJECT_TYPE_CREATURE, sRes, HW_Scatter(lAt, 1.0, 3.0),
                                  FALSE, HW_TAG_ALLY);
        if (!GetIsObjectValid(oSk)) continue;
        ChangeToStandardFaction(oSk, STANDARD_FACTION_DEFENDER);
        SetLocalInt(oSk, "SE_NO_RESPAWN", 1);
        SetLocalInt(oSk, "NO_LEASH", 1);
        SetName(oSk, GetName(oPC) + "'s Restless Dead");
        SetLocalObject(oSk, "hw_owner", oPC);
        effect e = EffectLinkEffects(EffectTemporaryHitpoints(nLevel * 20),
                                     EffectACIncrease(nLevel / 5));
        ApplyEffectToObject(DURATION_TYPE_PERMANENT, SupernaturalEffect(e), oSk);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_SUMMON_UNDEAD), oSk);
        AssignCommand(oSk, ActionForceFollowObject(oPC, 3.0));
        DestroyObject(oSk, fLife);
    }
}

void HW_HealPulse(object oMarker, int nHeal, int nLeft)
{
    if (!GetIsObjectValid(oMarker)) return;
    if (nLeft <= 0) { DestroyObject(oMarker); return; }
    location l = GetLocation(oMarker);
    object o = GetFirstObjectInShape(SHAPE_SPHERE, 5.0, l, FALSE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        object oOwner = GetLocalObject(oMarker, "hw_owner");
        if (!GetIsDead(o) && (o == oOwner || GetIsFriend(o, oOwner)))
        {
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(nHeal), o);
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_HEALING_S), o);
        }
        o = GetNextObjectInShape(SHAPE_SPHERE, 5.0, l, FALSE, OBJECT_TYPE_CREATURE);
    }
    DelayCommand(6.0, HW_HealPulse(oMarker, nHeal, nLeft - 1));
}

// A friendly jack-o'-lantern that heals oOwner's allies within 5m each round
// for 30 seconds (Harvest Moon). Plot and unusable: it is a ward, not a target.
void HW_HealingPumpkin(object oOwner, location lAt)
{
    object oPk = CreateObject(OBJECT_TYPE_PLACEABLE, "hw_pumpkin1", lAt, FALSE, HW_TAG_WARD);
    if (!GetIsObjectValid(oPk)) return;
    SetPlotFlag(oPk, TRUE);
    SetUseableFlag(oPk, FALSE);
    SetName(oPk, "Harvest Ward");
    SetLocalObject(oPk, "hw_owner", oOwner);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(EffectVisualEffect(VFX_DUR_LIGHT_ORANGE_10)), oPk);
    AssignCommand(GetModule(), HW_HealPulse(oPk, 50, 5));
}

// ---------------------------------------------------------------- worn prize effects

int HW_HasFx(object oPC, string sTag)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == sTag) return TRUE;
        e = GetNextEffect(oPC);
    }
    return FALSE;
}

void HW_StripFx(object oPC, string sTag)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == sTag) RemoveEffect(oPC, e);
        e = GetNextEffect(oPC);
    }
}

int HW_Wears(object oPC, int nSlot, string sTag)
{
    return GetTag(GetItemInSlot(nSlot, oPC)) == sTag;
}

void HW_FxIf(object oPC, int bWant, string sTag, effect eFx)
{
    int bHas = HW_HasFx(oPC, sTag);
    if (bWant && !bHas)
        ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            TagEffect(SupernaturalEffect(eFx), sTag), oPC);
    else if (!bWant && bHas)
        HW_StripFx(oPC, sTag);
}

// Make the prizes' always-on effects match what the PC is wearing / carrying.
// Called on equip / unequip, and once a minute for every PC from hw_tick - which
// is what puts them back after a login, a death or a respawn strip, with no
// login-frame work at all.
void HW_RefreshPrizeFx(object oPC)
{
    // Crown: Dread of the Harvest, a 10m aura (enter/exit scripts apply and
    // lift the penalty on hostiles).
    HW_FxIf(oPC, HW_Wears(oPC, INVENTORY_SLOT_HEAD, "hw26_crown"), "hw_fx_dread",
        EffectAreaOfEffect(AOE_MOB_HORRIFICAPPEARANCE, "hw_dread_en", "", "hw_dread_ex"));
    // Jack's Grin: the burning-head glow.
    HW_FxIf(oPC, HW_Wears(oPC, INVENTORY_SLOT_HEAD, "hw26_grin"), "hw_fx_grin",
        EffectVisualEffect(VFX_DUR_AURA_PULSE_ORANGE_BLACK));
    // Candlewick Ring: orange glow on the hands.
    HW_FxIf(oPC, HW_Wears(oPC, INVENTORY_SLOT_LEFTRING, "hw26_ring")
              || HW_Wears(oPC, INVENTORY_SLOT_RIGHTRING, "hw26_ring"), "hw_fx_ring",
        EffectVisualEffect(VFX_DUR_GLOW_LIGHT_ORANGE));
    // Ghost-Lantern: an ioun-stone wisp while switched on and carried.
    object oWisp = GetItemPossessedBy(oPC, "hw26_wisp");
    int bWisp = GetIsObjectValid(oWisp) && GetLocalInt(oWisp, "hw_on");
    HW_FxIf(oPC, bWisp, "hw_fx_wisp",
        EffectLinkEffects(EffectVisualEffect(VFX_DUR_IOUNSTONE_RED),
            EffectLinkEffects(EffectSkillIncrease(SKILL_SPOT, 5),
                              EffectSkillIncrease(SKILL_LISTEN, 5))));
}

// ---------------------------------------------------------------- hearths

object HW_PlaceHearth(location l)
{
    object o = CreateObject(OBJECT_TYPE_PLACEABLE, "hw_hearth", l, FALSE, HW_TAG_HEARTH);
    if (GetIsObjectValid(o))
        ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            SupernaturalEffect(EffectVisualEffect(VFX_DUR_LIGHT_ORANGE_15)), o);
    return o;
}

void HW_RestoreHearths()
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT area_tag, x, y, z, f, pc_name, year FROM hw_hearth");
    while (SqlStep(q))
    {
        object oArea = GetObjectByTag(SqlGetString(q, 0));
        if (!GetIsObjectValid(oArea)) continue;
        object o = HW_PlaceHearth(Location(oArea,
            Vector(SqlGetFloat(q, 1), SqlGetFloat(q, 2), SqlGetFloat(q, 3)), SqlGetFloat(q, 4)));
        SetName(o, SqlGetString(q, 5) + "'s Harvest Hearth (" + IntToString(SqlGetInt(q, 6)) + ")");
    }
}

// ---------------------------------------------------------------- claim

// This character's prize tier for this year: 1 (ranks 1-3), 2 (ranks 4-10),
// 3 (anyone else with HW_TIER3_MIN_GUTS+), 0 nothing.
int HW_ClaimTier(object oPC)
{
    int nRank = HW_Rank(oPC);
    if (nRank >= 1 && nRank <= 3)  return 1;
    if (nRank >= 4 && nRank <= 10) return 2;
    if (HW_GetGuts(oPC) >= HW_TIER3_MIN_GUTS) return 3;
    return 0;
}

int HW_Claimed(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT claimed FROM hw_guts WHERE year=@y AND ident=@i");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindString(q, "@i", HW_Ident(oPC));
    return SqlStep(q) && SqlGetInt(q, 0) != 0;
}

// The prize catalogue: which tier each year-stamped resref belongs to.
int HW_PrizeTier(string sRes)
{
    if (sRes == "hw26_crown" || sRes == "hw26_grin" || sRes == "hw26_mantle" || sRes == "hw26_scythe") return 1;
    if (sRes == "hw26_shroud" || sRes == "hw26_gaunt" || sRes == "hw26_lantern" || sRes == "hw26_pail") return 2;
    if (sRes == "hw26_charm" || sRes == "hw26_ring" || sRes == "hw26_hearth" || sRes == "hw26_wisp") return 3;
    return 0;
}
