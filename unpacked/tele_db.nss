// tele_db.nss — Rest-menu teleport persistence (merit redemptions 101-107).
//
// Reuses the campaign SQLite DB "meritdb". Saved positions are PER CHARACTER
// (keyed by GetObjectUUID), while the unlock entitlements themselves live in the
// merit redemptions table and are per-CD-Key (see merit_redeem.nss).
//
// Tables:
//   tele_slots(pid, slot, area, name, x, y, z, facing)
//     slot 0     = last Well-of-Eru return point (armed by the rest-menu
//                  "To. The Well of Eru." teleport only; death never arms it)
//     slot 1..5  = dedicated rewriteable save-slots
//   tele_state(pid, return_armed)
//     return_armed = 1 after a Well-of-Eru teleport, cleared on a return jump,
//     so the return can never be used twice in a row.

const string TELE_DB = "meritdb";

// ------------------------------------------------------------
// Schema

void Tele_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "CREATE TABLE IF NOT EXISTS tele_slots (" +
        "pid TEXT NOT NULL," +
        "slot INTEGER NOT NULL," +
        "area TEXT," +
        "name TEXT," +
        "x REAL, y REAL, z REAL, facing REAL," +
        "PRIMARY KEY(pid, slot))");
    SqlStep(q);

    sqlquery qs = SqlPrepareQueryCampaign(TELE_DB,
        "CREATE TABLE IF NOT EXISTS tele_state (" +
        "pid TEXT PRIMARY KEY," +
        "return_armed INTEGER NOT NULL DEFAULT 0)");
    SqlStep(qs);
}

// ------------------------------------------------------------
// Saved slots

// Store the PC's current area + position/facing into nSlot (upsert).
void Tele_SaveSlot(object oPC, int nSlot)
{
    object oArea = GetArea(oPC);
    if (!GetIsObjectValid(oArea)) return;
    vector v = GetPosition(oPC);

    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "INSERT INTO tele_slots(pid, slot, area, name, x, y, z, facing)" +
        " VALUES(@p, @s, @a, @n, @x, @y, @z, @f)" +
        " ON CONFLICT(pid, slot) DO UPDATE SET" +
        " area=excluded.area, name=excluded.name," +
        " x=excluded.x, y=excluded.y, z=excluded.z, facing=excluded.facing");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@s", nSlot);
    SqlBindString(q, "@a", GetResRef(oArea));
    SqlBindString(q, "@n", GetName(oArea));
    SqlBindFloat(q, "@x", v.x);
    SqlBindFloat(q, "@y", v.y);
    SqlBindFloat(q, "@z", v.z);
    SqlBindFloat(q, "@f", GetFacing(oPC));
    SqlStep(q);
}

// TRUE if nSlot has a saved location for this character.
int Tele_HasSlot(object oPC, int nSlot)
{
    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "SELECT 1 FROM tele_slots WHERE pid=@p AND slot=@s LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@s", nSlot);
    return SqlStep(q);
}

// Stored area name for nSlot, or "Unused" when unbound.
string Tele_SlotName(object oPC, int nSlot)
{
    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "SELECT name FROM tele_slots WHERE pid=@p AND slot=@s LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@s", nSlot);
    if (SqlStep(q))
    {
        string sName = SqlGetString(q, 0);
        if (sName != "") return sName;
    }
    return "Unused";
}

// Resolve a saved slot into a usable location. There is no get-area-by-resref
// builtin, so we scan the module's areas for a matching ResRef. Returns an
// invalid location (area OBJECT_INVALID) when the slot is unbound or its area
// no longer exists.
location Tele_SlotLocation(object oPC, int nSlot)
{
    // Sentinel with an invalid area, so Tele_DoJump's GetAreaFromLocation guard
    // rejects it (GetStartingLocation would be a *valid* area and teleport the
    // player to the module start instead).
    vector vZero;
    location lInvalid = Location(OBJECT_INVALID, vZero, 0.0);

    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "SELECT area, x, y, z, facing FROM tele_slots WHERE pid=@p AND slot=@s LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@s", nSlot);
    if (!SqlStep(q)) return lInvalid;

    string sArea = SqlGetString(q, 0);
    vector v;
    v.x = SqlGetFloat(q, 1);
    v.y = SqlGetFloat(q, 2);
    v.z = SqlGetFloat(q, 3);
    float fFacing = SqlGetFloat(q, 4);

    object oArea = GetFirstArea();
    while (GetIsObjectValid(oArea))
    {
        if (GetResRef(oArea) == sArea)
            return Location(oArea, v, fFacing);
        oArea = GetNextArea();
    }
    return lInvalid;
}

// Validated jump: clears actions, applies a teleport VFX, jumps. Mirrors the
// voidportal.nss idiom. Does nothing if the location's area is invalid.
void Tele_DoJump(object oPC, location lLoc)
{
    if (GetAreaFromLocation(lLoc) == OBJECT_INVALID)
    {
        SendMessageToPC(oPC, "[Teleport] That destination is no longer reachable.");
        return;
    }
    effect eVis = EffectVisualEffect(VFX_FNF_LOS_NORMAL_30);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oPC);
    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, ActionJumpToLocation(lLoc));
}

// ------------------------------------------------------------
// Return-armed flag (Well-of-Eru one-shot return)

int Tele_GetArmed(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "SELECT return_armed FROM tele_state WHERE pid=@p LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

void Tele_SetArmed(object oPC, int bArmed)
{
    sqlquery q = SqlPrepareQueryCampaign(TELE_DB,
        "INSERT INTO tele_state(pid, return_armed) VALUES(@p, @a)" +
        " ON CONFLICT(pid) DO UPDATE SET return_armed=excluded.return_armed");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@a", bArmed);
    SqlStep(q);
}
