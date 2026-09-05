// graf_nui_inc.nss - the little NUI form that captures the graffiti's name and
// description. A conversation cannot take typed input, so this is the one bit
// of the easel that is not a dialogue node. Shaped after dye_nui_inc.nss.
#include "nw_inc_nui"
#include "graf_inc"

const string GRAF_NUI_ID  = "graffiti";
const string GRAF_NUI_TOK = "GRAF_TOK";

const int GRAF_NAME_MAX  = 40;
const int GRAF_DESCR_MAX = 240;

json Graf_NuiWindow(object oPC);
void Graf_NuiSave(object oPC);

json Graf_NuiWindow(object oPC)
{
    json jCol = JsonArray();

    jCol = JsonArrayInsert(jCol, NuiHeight(NuiLabel(
        JsonString("Your mark on the Well of Eru"),
        JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 22.0));

    jCol = JsonArrayInsert(jCol, NuiHeight(NuiLabel(
        JsonString("Name (what hovering over it shows)"),
        JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE)), 18.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiId(NuiTextEdit(
        JsonString("Frodo was here"), NuiBind("gname"), GRAF_NAME_MAX, FALSE),
        "gname"), 28.0));

    jCol = JsonArrayInsert(jCol, NuiHeight(NuiLabel(
        JsonString("Description (what examining it reads)"),
        JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE)), 18.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiId(NuiTextEdit(
        JsonString("- and the road goes ever on"), NuiBind("gdescr"),
        GRAF_DESCR_MAX, TRUE), "gdescr"), 110.0));

    jCol = JsonArrayInsert(jCol, NuiHeight(NuiLabel(NuiBind("gstat"),
        JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 20.0));

    json jFoot = JsonArray();
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Save")), "bsave"));
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Close")), "bclose"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    float ww = 420.0;
    float wh = 300.0;
    float wx = -1.0;
    float wy = -1.0;
    int gw = GetPlayerDeviceProperty(oPC, PLAYER_DEVICE_PROPERTY_GUI_WIDTH);
    int gh = GetPlayerDeviceProperty(oPC, PLAYER_DEVICE_PROPERTY_GUI_HEIGHT);
    if (gw > 0 && gh > 0)
    {
        wx = (IntToFloat(gw) - ww) / 2.0;
        wy = (IntToFloat(gh) - wh) / 2.0;
        if (wx < 0.0) wx = 0.0;
        if (wy < 0.0) wy = 0.0;
    }

    return NuiWindow(NuiCol(jCol), JsonString("Your Mark"),
        NuiRect(wx, wy, ww, wh),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

void Graf_NuiSave(object oPC)
{
    int nTok = GetLocalInt(oPC, GRAF_NUI_TOK);
    if (nTok == 0) return;

    string sName  = Graf_Sanitize(JsonGetString(NuiGetBind(oPC, nTok, "gname")),
                                  GRAF_NAME_MAX);
    string sDescr = Graf_Sanitize(JsonGetString(NuiGetBind(oPC, nTok, "gdescr")),
                                  GRAF_DESCR_MAX);

    Graf_SetText(oPC, sName, sDescr);
    Graf_RenderFor(oPC);        // the canvas carries the new text immediately
    NuiSetBind(oPC, nTok, "gstat", JsonString("Saved. The stone reads it now."));
}
