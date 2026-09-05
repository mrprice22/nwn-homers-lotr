// graf_inc.nss - the Well of Eru graffiti easel: canvas rendering, the claim
// lock, and the paged category/appearance menus behind graf_conv.dlg.
//
// WHY A PEDESTAL AND A CANVAS, AND NOT ONE OBJECT
// NWScript has no SetPlaceableAppearance, and NWNX_Object_SetAppearance is
// documented "will not update for PCs until they re-enter the area" - so the
// only way to show a live change is to destroy the placeable and create a new
// one with the new look, which would end any conversation that object was
// hosting. Hence two objects: the PEDESTAL you talk to (permanent, tag
// graf_pedestal) and the CANVAS that changes (respawned on every pick, tag
// graf_canvas). The appearance is set in the same script frame as the
// CreateObject, so clients never see the placeholder look.
//
// Tokens 6500-6518 (see CLAUDE-graffiti.md):
//   6500 heading   6501 "Page x of y"   6502 current-selection summary
//   6510-6518      the nine row labels
// Per-PC locals: graf_mode (0 themes / 1 categories / 2 appearances),
//   graf_theme, graf_cat, graf_page_off, graf_page_total,
//   graf_slot_<i> (string) / graf_slot_<i>_id.

#include "graf_db"
#include "nwnx_object"

const string GRAF_PEDESTAL = "graf_pedestal";
const string GRAF_CANVAS   = "graf_canvas";
// Optional toolset override: place a waypoint with this tag to pin the canvas
// somewhere other than 2m in front of the pedestal.
const string GRAF_CANVAS_WP = "wp_graffiti_canvas";

const int GRAF_PAGE = 9;

// How far out from the pedestal the canvas stands, in metres, along the
// pedestal's own facing. 3.0 puts it hard against the alcove's east wall;
// the wp_graffiti_canvas waypoint overrides position and facing outright.
const float GRAF_CANVAS_DIST = 3.0;

int      Graf_Now();
object   Graf_Pedestal();
location Graf_CanvasLoc();
object   Graf_Render(int nAppearance, string sName, string sDescr);
void     Graf_RenderFor(object oPC);
void     Graf_RestoreCanvas();
int      Graf_ClaimOk(object oPC);
string   Graf_ClaimHolder();
void     Graf_Release(object oPC);
void     Graf_Summary(object oPC);
void     Graf_BuildThemePage(object oPC);
void     Graf_BuildCatPage(object oPC);
void     Graf_BuildAppPage(object oPC);
void     Graf_BuildPage(object oPC);
void     Graf_Step(object oPC, int nDelta);

// ------------------------------------------------------------ helpers

int Graf_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB, "SELECT CAST(strftime('%s','now') AS INTEGER)");
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

object Graf_Pedestal()
{
    return GetObjectByTag(GRAF_PEDESTAL);
}

location Graf_CanvasLoc()
{
    object oWP = GetWaypointByTag(GRAF_CANVAS_WP);
    if (GetIsObjectValid(oWP)) return GetLocation(oWP);

    object oPed = Graf_Pedestal();
    if (!GetIsObjectValid(oPed)) return GetStartingLocation();

    // GRAF_CANVAS_DIST out along the pedestal's facing, so the canvas stands in
    // front of it and follows if the admin moves the pedestal in the toolset.
    float f = GetFacing(oPed);
    vector v = GetPosition(oPed);
    vector d = AngleToVector(f);          // degrees -> unit direction
    vector vOut = Vector(v.x + GRAF_CANVAS_DIST * d.x,
                         v.y + GRAF_CANVAS_DIST * d.y, v.z);
    return Location(GetArea(oPed), vOut, f);
}

// ------------------------------------------------------------ the canvas

// Respawn the canvas with the given look and text. Returns the new object.
object Graf_Render(int nAppearance, string sName, string sDescr)
{
    object oPed = Graf_Pedestal();
    if (!GetIsObjectValid(oPed)) return OBJECT_INVALID;

    object oOld = GetLocalObject(oPed, "graf_canvas_obj");
    if (!GetIsObjectValid(oOld)) oOld = GetObjectByTag(GRAF_CANVAS);
    if (GetIsObjectValid(oOld)) DestroyObject(oOld);

    object oNew = CreateObject(OBJECT_TYPE_PLACEABLE, GRAF_CANVAS, Graf_CanvasLoc());
    if (!GetIsObjectValid(oNew)) return OBJECT_INVALID;

    // Same frame as the creation: the client's first sight of this object
    // already carries the chosen appearance.
    if (nAppearance > 0) NWNX_Object_SetAppearance(oNew, nAppearance);
    if (sName != "")  SetName(oNew, sName);
    if (sDescr != "") SetDescription(oNew, sDescr, TRUE);

    SetLocalObject(oPed, "graf_canvas_obj", oNew);
    return oNew;
}

void Graf_RenderFor(object oPC)
{
    struct graf_pick p = Graf_GetPick(oPC);
    if (p.appearance <= 0) return;

    string sName = p.name;
    if (sName == "") sName = "Unnamed mark";
    Graf_Render(p.appearance, sName, p.descr);
    Graf_SetState("shown", GetPCPublicCDKey(oPC), p.appearance);
}

// Called from onmoduleload: bring back whatever the easel was last showing.
// Created placeables do not survive a reboot, and the whole point of the easel
// is that a pick does.
void Graf_RestoreCanvas()
{
    string sKey = Graf_State("shown");
    if (sKey == "") return;

    sqlquery q = SqlPrepareQueryCampaign(GRAF_DB,
        "SELECT appearance, name, descr FROM picks WHERE cdkey=@k");
    SqlBindString(q, "@k", sKey);
    if (!SqlStep(q)) return;

    int nApp = SqlGetInt(q, 0);
    if (nApp <= 0) return;
    string sName = SqlGetString(q, 1);
    if (sName == "") sName = "Unnamed mark";
    Graf_Render(nApp, sName, SqlGetString(q, 2));
}

// ------------------------------------------------------------ claim lock

string Graf_ClaimHolder()
{
    if (Graf_Now() - Graf_StateInt("claim") > GRAF_CLAIM_TTL) return "";
    return Graf_State("claim");
}

// TRUE if oPC may use the easel; refreshes the claim when it does.
int Graf_ClaimOk(object oPC)
{
    string sMine = GetPCPublicCDKey(oPC);
    string sHeld = Graf_ClaimHolder();
    if (sHeld != "" && sHeld != sMine) return FALSE;
    Graf_SetState("claim", sMine, Graf_Now());
    return TRUE;
}

void Graf_Release(object oPC)
{
    if (Graf_State("claim") != GetPCPublicCDKey(oPC)) return;
    Graf_SetState("claim", "", 0);
}

// ------------------------------------------------------------ menus

void Graf_Summary(object oPC)
{
    struct graf_pick p = Graf_GetPick(oPC);
    if (p.appearance <= 0)
    {
        SetCustomToken(6502, "Nothing chosen yet - the stone is blank.");
        return;
    }
    string s = p.app_name + "  (" + p.category + ")";
    if (p.name != "")  s += "\n  Named:  " + p.name;
    if (p.descr != "") s += "\n  Reads:  " + p.descr;
    SetCustomToken(6502, s);
}

// Shared page scaffolding: heading, "Page x of y", and a wiped slot set.
void Graf_PageHeader(object oPC, string sHeading, int nTotal)
{
    int nOff = GetLocalInt(oPC, "graf_page_off");
    SetLocalInt(oPC, "graf_page_total", nTotal);

    int nPages = (nTotal + GRAF_PAGE - 1) / GRAF_PAGE;
    if (nPages == 0) nPages = 1;
    SetCustomToken(6500, sHeading);
    SetCustomToken(6501, "Page " + IntToString(nOff / GRAF_PAGE + 1)
                       + " of " + IntToString(nPages));

    int i;
    for (i = 0; i < GRAF_PAGE; i++)
    {
        DeleteLocalString(oPC, "graf_slot_" + IntToString(i));
        SetLocalInt(oPC, "graf_slot_" + IntToString(i) + "_id", 0);
        SetCustomToken(6510 + i, "");
    }
}

// Level 1 of 3. Nine themes exactly, which is one page - that is the whole
// reason themes exist. CEP's own 289 categories were 33 pages of paging before
// the player saw a single model.
void Graf_BuildThemePage(object oPC)
{
    Graf_PageHeader(oPC, "What sort of thing?", Graf_ThemeTotal());

    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT t.name, t.n, (SELECT COUNT(*) FROM appearances a"
        + "  JOIN categories c ON c.name = a.category WHERE c.theme = t.name)"
        + " FROM themes t ORDER BY t.sort LIMIT 9 OFFSET @o");
    SqlBindInt(q, "@o", GetLocalInt(oPC, "graf_page_off"));
    int i = 0;
    while (SqlStep(q) && i < GRAF_PAGE)
    {
        string sTheme = SqlGetString(q, 0);
        SetLocalString(oPC, "graf_slot_" + IntToString(i), sTheme);
        SetCustomToken(6510 + i, sTheme + "  ("
            + IntToString(SqlGetInt(q, 2)) + " in "
            + IntToString(SqlGetInt(q, 1)) + " kinds)");
        i++;
    }
}

// Level 2 of 3: the categories inside one theme, biggest first (the publisher
// sorts them that way, so page 1 of a theme is always its useful half).
void Graf_BuildCatPage(object oPC)
{
    string sTheme = GetLocalString(oPC, "graf_theme");
    Graf_PageHeader(oPC, sTheme, Graf_ThemeSize(sTheme));

    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT name, n FROM categories WHERE theme=@t"
        + " ORDER BY sort LIMIT 9 OFFSET @o");
    SqlBindString(q, "@t", sTheme);
    SqlBindInt(q, "@o", GetLocalInt(oPC, "graf_page_off"));
    int i = 0;
    while (SqlStep(q) && i < GRAF_PAGE)
    {
        string sCat = SqlGetString(q, 0);
        SetLocalString(oPC, "graf_slot_" + IntToString(i), sCat);
        SetCustomToken(6510 + i, sCat + "  (" + IntToString(SqlGetInt(q, 1)) + ")");
        i++;
    }
}

// Level 3 of 3: the looks themselves.
void Graf_BuildAppPage(object oPC)
{
    string sCat = GetLocalString(oPC, "graf_cat");
    Graf_PageHeader(oPC, GetLocalString(oPC, "graf_theme") + " > " + sCat,
                    Graf_CatSize(sCat));

    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT id, name, sort FROM appearances WHERE category=@c"
        + " ORDER BY sort LIMIT 9 OFFSET @o");
    SqlBindString(q, "@c", sCat);
    SqlBindInt(q, "@o", GetLocalInt(oPC, "graf_page_off"));
    int i = 0;
    while (SqlStep(q) && i < GRAF_PAGE)
    {
        int nId = SqlGetInt(q, 0);
        SetLocalString(oPC, "graf_slot_" + IntToString(i), IntToString(nId));
        SetLocalInt(oPC, "graf_slot_" + IntToString(i) + "_id", nId);
        SetLocalInt(oPC, "graf_slot_" + IntToString(i) + "_pos", SqlGetInt(q, 2));
        SetCustomToken(6510 + i, SqlGetString(q, 1));
        i++;
    }
}

// Repaint whichever of the three levels is showing.
void Graf_BuildPage(object oPC)
{
    int nMode = GetLocalInt(oPC, "graf_mode");
    if (nMode == 2)      Graf_BuildAppPage(oPC);
    else if (nMode == 1) Graf_BuildCatPage(oPC);
    else                 Graf_BuildThemePage(oPC);
}

// Step one appearance forward/back inside the category on screen (or, from the
// top menu, the current pick's own category), so the player can nudge through
// neighbouring looks without clicking every row of every page. Wraps at both
// ends, and drags the paged list along with it when the list is up.
void Graf_Step(object oPC, int nDelta)
{
    struct graf_pick p = Graf_GetPick(oPC);
    // While the model list is up, the category on screen is the one to step
    // through - otherwise stepping would walk the picked model's category and
    // repaint a list that is showing a different one.
    string sCat = "";
    if (GetLocalInt(oPC, "graf_mode") == 2) sCat = GetLocalString(oPC, "graf_cat");
    if (sCat == "") sCat = p.category;
    if (sCat == "") sCat = GetLocalString(oPC, "graf_cat");
    if (sCat == "")
    {
        // Nothing chosen yet: start at the head of the first theme.
        string sTheme = Graf_ThemeAt(0);
        sCat = Graf_CatAt(sTheme, 0);
        SetLocalString(oPC, "graf_theme", sTheme);
        SetLocalString(oPC, "graf_cat", sCat);
        Graf_SetAppearance(oPC, Graf_AppAt(sCat, 0));
        Graf_RenderFor(oPC);
        SetLocalInt(oPC, "graf_page_off", 0);
        if (GetLocalInt(oPC, "graf_mode") == 2) Graf_BuildAppPage(oPC);
        return;
    }
    // Keep the breadcrumb honest when the pick came from a previous session.
    if (GetLocalString(oPC, "graf_theme") == "")
        SetLocalString(oPC, "graf_theme", Graf_CatThemeOf(sCat));

    // The sort position counts only when the current pick actually lives in the
    // category being stepped; if it does not, step onto that category's head.
    int nPos = 0;
    int nHave = FALSE;
    sqlquery q = SqlPrepareQueryCampaign(GRAF_CAT,
        "SELECT sort FROM appearances WHERE id=@i AND category=@c");
    SqlBindInt(q, "@i", p.appearance);
    SqlBindString(q, "@c", sCat);
    if (SqlStep(q))
    {
        nPos = SqlGetInt(q, 0);
        nHave = TRUE;
    }

    // The same wrap Graf_AppAt does internally, done here as well so we know
    // WHICH row we landed on - that is what lets the browse list follow along.
    int nSize = Graf_CatSize(sCat);
    if (nSize <= 0) return;
    int nNew = 0;
    if (nHave) nNew = nPos + nDelta;
    while (nNew < 0)      nNew += nSize;
    while (nNew >= nSize) nNew -= nSize;

    int nId = Graf_AppAt(sCat, nNew);
    if (nId <= 0) return;
    Graf_SetAppearance(oPC, nId);
    Graf_RenderFor(oPC);

    // Keep the paged menu on the page that holds the model now showing, so
    // stepping past a page boundary does not leave a stale list behind.
    SetLocalInt(oPC, "graf_page_off", (nNew / GRAF_PAGE) * GRAF_PAGE);
    if (GetLocalInt(oPC, "graf_mode") == 2) Graf_BuildAppPage(oPC);
}
