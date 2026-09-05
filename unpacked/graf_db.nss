// graf_db.nss - storage + catalogue reads for the Well of Eru graffiti easel.
//
// Two campaign DBs are involved and they do different jobs:
//
//   placeappdb  READ-ONLY reference, ~9,500 rows, published from the host by
//               bin/publish-placeable-db.py out of module-index/
//               placeable_appearances.json. Every placeable *appearance* in the
//               module's haks, with a CEP category. Never written from game.
//   graffitidb  per-season player state: each CD key's in-progress pick, and
//               the easel's own claim/last-rendered state.
//
// The pick survives a cancelled conversation, a logout and a reboot on purpose -
// the player is choosing a permanent monument, not browsing a shop. See
// CLAUDE-graffiti.md.

const string GRAF_DB  = "graffitidb";
const string GRAF_CAT = "placeappdb";

// How long a claim on the easel survives with no interaction, in seconds.
const int GRAF_CLAIM_TTL = 180;

struct graf_pick
{
    int    found;
    int    appearance;
    string app_name;
    string category;
    string name;
    string descr;
};

void          Graf_InitDb();
struct graf_pick Graf_GetPick(object oPC);
void          Graf_SetAppearance(object oPC, int nId);
void          Graf_SetText(object oPC, string sName, string sDescr);
string        Graf_State(string sKey);
void          Graf_SetState(string sKey, string sVal, int nVal = 0);
int           Graf_StateInt(string sKey);
string        Graf_AppName(int nId);
string        Graf_AppCategory(int nId);
int           Graf_ThemeTotal();
int           Graf_ThemeSize(string sTheme);
int           Graf_CatSize(string sCat);
string        Graf_CatThemeOf(string sCat);
string        Graf_CatAt(string sTheme, int nIndex);
string        Graf_ThemeAt(int nIndex);
int           Graf_AppAt(string sCat, int nIndex);
string        Graf_Sanitize(string s, int nMax);

// ------------------------------------------------------------ schema

void Graf_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB,
        "CREATE TABLE IF NOT EXISTS picks ("
        + "cdkey TEXT PRIMARY KEY,"
        + "appearance INTEGER NOT NULL DEFAULT 0,"
        + "app_name TEXT, category TEXT,"
        + "name TEXT, descr TEXT,"
        + "updated_at TEXT NOT NULL DEFAULT (datetime('now')))");
    SqlStep(q);

    // Single-row-per-key scratch table: 'claim' holds the CD key currently
    // working the easel (ival = unix time of the last interaction), 'shown'
    // holds the CD key whose pick the canvas is currently displaying, so
    // Graf_RestoreCanvas can rebuild it after a reboot.
    q = SqlPrepareQueryCampaign(GRAF_DB,
        "CREATE TABLE IF NOT EXISTS easel ("
        + "skey TEXT PRIMARY KEY, ival INTEGER NOT NULL DEFAULT 0, sval TEXT,"
        + "updated_at TEXT NOT NULL DEFAULT (datetime('now')))");
    SqlStep(q);
}

// ------------------------------------------------------------ the pick

struct graf_pick Graf_GetPick(object oPC)
{
    struct graf_pick p;
    p.found = FALSE;
    p.appearance = 0;

    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB,
        "SELECT appearance, app_name, category, name, descr FROM picks WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (SqlStep(q))
    {
        p.found      = TRUE;
        p.appearance = SqlGetInt(q, 0);
        p.app_name   = SqlGetString(q, 1);
        p.category   = SqlGetString(q, 2);
        p.name       = SqlGetString(q, 3);
        p.descr      = SqlGetString(q, 4);
    }
    return p;
}

void Graf_SetAppearance(object oPC, int nId)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB,
        "INSERT INTO picks (cdkey, appearance, app_name, category, updated_at)"
        + " VALUES (@k, @a, @n, @c, datetime('now'))"
        + " ON CONFLICT(cdkey) DO UPDATE SET appearance=@a, app_name=@n,"
        + " category=@c, updated_at=datetime('now')");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindInt(q, "@a", nId);
    SqlBindString(q, "@n", Graf_AppName(nId));
    SqlBindString(q, "@c", Graf_AppCategory(nId));
    SqlStep(q);
}

void Graf_SetText(object oPC, string sName, string sDescr)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB,
        "INSERT INTO picks (cdkey, name, descr, updated_at)"
        + " VALUES (@k, @n, @d, datetime('now'))"
        + " ON CONFLICT(cdkey) DO UPDATE SET name=@n, descr=@d,"
        + " updated_at=datetime('now')");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", sName);
    SqlBindString(q, "@d", sDescr);
    SqlStep(q);
}

// ------------------------------------------------------------ easel state

string Graf_State(string sKey)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB, "SELECT sval FROM easel WHERE skey=@s");
    SqlBindString(q, "@s", sKey);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return "";
}

int Graf_StateInt(string sKey)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB, "SELECT ival FROM easel WHERE skey=@s");
    SqlBindString(q, "@s", sKey);
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

void Graf_SetState(string sKey, string sVal, int nVal = 0)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB,
        "INSERT INTO easel (skey, ival, sval, updated_at)"
        + " VALUES (@s, @i, @v, datetime('now'))"
        + " ON CONFLICT(skey) DO UPDATE SET ival=@i, sval=@v, updated_at=datetime('now')");
    SqlBindString(q, "@s", sKey);
    SqlBindInt(q, "@i", nVal);
    SqlBindString(q, "@v", sVal);
    SqlStep(q);
}

// ------------------------------------------------------------ catalogue

string Graf_AppName(int nId)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT, "SELECT name FROM appearances WHERE id=@i");
    SqlBindInt(q, "@i", nId);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return "";
}

string Graf_AppCategory(int nId)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT, "SELECT category FROM appearances WHERE id=@i");
    SqlBindInt(q, "@i", nId);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return "";
}

int Graf_ThemeTotal()
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT, "SELECT COUNT(*) FROM themes");
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

// How many CATEGORIES a theme holds (not appearances) - it is the row count the
// category page pages through.
int Graf_ThemeSize(string sTheme)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT, "SELECT n FROM themes WHERE name=@t");
    SqlBindString(q, "@t", sTheme);
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

int Graf_CatSize(string sCat)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT, "SELECT n FROM categories WHERE name=@c");
    SqlBindString(q, "@c", sCat);
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

string Graf_CatThemeOf(string sCat)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT theme FROM categories WHERE name=@c");
    SqlBindString(q, "@c", sCat);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return "";
}

// Category name at position nIndex within a theme.
string Graf_CatAt(string sTheme, int nIndex)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT name FROM categories WHERE theme=@t ORDER BY sort LIMIT 1 OFFSET @o");
    SqlBindString(q, "@t", sTheme);
    SqlBindInt(q, "@o", nIndex);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return "";
}

// Theme name at position nIndex in the published order.
string Graf_ThemeAt(int nIndex)
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT name FROM themes ORDER BY sort LIMIT 1 OFFSET @o");
    SqlBindInt(q, "@o", nIndex);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return "";
}

// Appearance id at position nIndex within a category (wraps at both ends, so
// "next"/"previous" from the first or last entry never dead-ends).
int Graf_AppAt(string sCat, int nIndex)
{
    int nSize = Graf_CatSize(sCat);
    if (nSize <= 0) return 0;
    while (nIndex < 0)      nIndex += nSize;
    while (nIndex >= nSize) nIndex -= nSize;

    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT id FROM appearances WHERE category=@c ORDER BY sort LIMIT 1 OFFSET @o");
    SqlBindString(q, "@c", sCat);
    SqlBindInt(q, "@o", nIndex);
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

// Strip the two characters that would let player text impersonate a custom
// token or a colour sequence, and clamp the length. Everything the player types
// ends up in an NPC's dialogue line and in the DM's redemption note.
string Graf_Sanitize(string s, int nMax)
{
    string sOut = "";
    int i;
    int nLen = GetStringLength(s);
    for (i = 0; i < nLen; i++)
    {
        string c = GetSubString(s, i, 1);
        if (c == "<" || c == ">") continue;
        sOut += c;
    }
    if (GetStringLength(sOut) > nMax) sOut = GetSubString(sOut, 0, nMax);
    return sOut;
}
