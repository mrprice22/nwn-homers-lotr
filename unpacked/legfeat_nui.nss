// legfeat_nui.nss — the Legendary Feats picker window.
//
// Opened at character level 60 (legfeat_lvl, from NWNX_ON_LEVEL_UP_AFTER) and
// re-opened by finishing a rest while picks remain (on_mod_rest). Event handling
// is in legfeat_evt.nss, registered per-window via NuiCreate's sEventScript.
//
// WHY A CUSTOM PICKER. The engine's own level-up feat page hands out exactly one
// general feat at 60 to everybody, so the 1 / 2 / 3 allotment cannot be
// expressed to it — and legendary feats are deliberately invisible to it
// (ALLCLASSESCANUSE = 0 in feat.2da). This window is the only grant path.
//
// The window is REBUILT rather than updated after each pick: a taken feat turns
// from a button into a plain line, and the remaining-picks header changes. That
// is cheaper to get right than binding every row's enabled-state, and the list
// is short.
//
// Two traps already recorded against this repo's other NUI windows apply here:
// resrefs are capped at 16 characters, and nw_inc_nui has no `&` reference
// parameters. Both are respected below.
//
// LAYOUT: EVERY CHILD GETS AN EXPLICIT WIDTH, AND THE LIST GROUP AN EXPLICIT
// SIZE. The first build left the list group unsized and gave the description
// label no width, so the group sized itself to the description text: it took a
// fraction of the window, grew a horizontal scrollbar, and squeezed the header
// labels down to "You may choose 2 leg". dye_nui_inc.nss is the working
// precedent — one group, explicit NuiHeight. The row widths below sum to less
// than LEGFEAT_LIST_W, and the group scrolls vertically only, so no amount of
// content can reintroduce a horizontal scrollbar.

#include "nw_inc_nui"
#include "legfeat_inc"

const string LEGFEAT_WIN = "legfeats";     // NuiCreate window id
const string LEGFEAT_TOK = "LEGFEAT_TOK";  // PC local: this window's token

// The one line of tunable text under the "you may choose N" header. It exists
// because where a player re-picks is not settled — the re-pick node is parked on
// Ping Pong and will likely move — and the window should not have to be edited
// when it does. Set it to "" to drop the line entirely.
//
// It is appended to the "You may choose N legendary feats." header and shown on
// the SAME centred line, wrapping onto a second line only if the two together
// are too long — see LEGFEAT_HDR_WRAP_AT below for what that costs.
//
// BUDGET: header + subtitle together should stay under ~80 characters. See
// README.md "Tuning the picker's subtitle".
const string LEGFEAT_SUBTITLE = "Can repick with Ping Pong in Well of Eru";

// Where the header stops being one line.
//
// NUI forces a choice: a `label` centres but NEVER wraps (it clips silently —
// that is how the header once read "You may choose 2 leg"), while `text` wraps
// but cannot be aligned, so it is always left-justified. There is no centred
// wrapping control.
//
// So: at or under this many characters the header and subtitle share one centred
// label, which is the normal case and the one that looks right. Over it, they
// fall back to a two-line wrapping text box — left-justified, but readable,
// which beats clipping half the sentence. Keep the subtitle short and the
// fallback never fires.
//
// The threshold is characters against a proportional font, so it is an estimate,
// deliberately conservative: a player running a larger UI scale fits fewer
// characters per line than you do.
const int LEGFEAT_HDR_WRAP_AT = 80;

// Geometry. The three row columns sum to 660, comfortably inside the list
// group's 680, which is what keeps the horizontal scrollbar away.
const float LEGFEAT_WIN_W   = 720.0;
const float LEGFEAT_WIN_H   = 470.0;
const float LEGFEAT_LIST_W  = 680.0;
const float LEGFEAT_LIST_H  = 320.0;
const float LEGFEAT_COL_BTN = 80.0;
const float LEGFEAT_COL_NAME = 240.0;
const float LEGFEAT_COL_EFF  = 340.0;
const float LEGFEAT_ROW_H    = 30.0;
const float LEGFEAT_HDR_H    = 26.0;   // one centred line
const float LEGFEAT_SUB_H    = 40.0;   // two lines, wrapped fallback

json LegFeat_Window(object oPC);
void LegFeat_Open(object oPC);
void LegFeat_Close(object oPC);

// One list entry: either a "Take" button (id "t<index>") or, once taken, a
// plain line saying so.
json LegFeat_Row(object oPC, int nIndex, int nRemaining)
{
    int nFeatId = LegFeat_IdAt(nIndex);
    int bTaken  = LegFeat_HasPick(oPC, nFeatId);
    int bQualified = LegFeat_MeetsPrereq(oPC, nIndex);

    // The tooltip carries the prerequisite as well as the description, on every
    // row and whether or not it is met — a player deciding how to spend two
    // picks needs to see that Onslaught wants Assault BEFORE taking something
    // else. A greyed row with no visible reason is the complaint this avoids.
    string sTip = LegFeat_DescAt(nIndex);
    string sPrereq = LegFeat_PrereqAt(nIndex);
    if (sPrereq != "") sTip += "  (Requires: " + sPrereq + ")";

    json jRow = JsonArray();
    if (bTaken)
    {
        jRow = JsonArrayInsert(jRow, NuiWidth(
            NuiLabel(JsonString("taken"), JsonInt(NUI_HALIGN_CENTER),
                     JsonInt(NUI_VALIGN_MIDDLE)), LEGFEAT_COL_BTN));
    }
    else
    {
        json jBtn = NuiId(NuiButton(JsonString("Take")), "t" + IntToString(nIndex));
        // Greyed out rather than hidden when no picks are left or the
        // prerequisite is not met, so the player can still read the whole pool
        // and decide before spending. LegFeat_Take re-checks the prerequisite —
        // this window is only a snapshot of it.
        jBtn = NuiEnabled(jBtn, JsonBool(nRemaining > 0 && bQualified));
        jBtn = NuiTooltip(jBtn, JsonString(sTip));
        jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, LEGFEAT_COL_BTN));
    }

    // Name and a short effect summary. The full description is the tooltip on
    // both — an inline description is what forced the horizontal scrollbar.
    json jName = NuiLabel(JsonString(LegFeat_NameAt(nIndex)),
                          JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jName = NuiTooltip(jName, JsonString(sTip));
    jRow = JsonArrayInsert(jRow, NuiWidth(jName, LEGFEAT_COL_NAME));

    // An unqualified row shows what it wants instead of what it gives: the
    // effect is moot until the prerequisite is met, and "Requires: ..." in the
    // column the eye is already on beats a tooltip nobody hovers. Kept short —
    // a NUI label clips silently rather than wrapping (see the header note).
    string sEff = LegFeat_EffectAt(nIndex);
    if (!bTaken && !bQualified) sEff = "Requires: " + sPrereq;
    json jEff = NuiLabel(JsonString(sEff),
                         JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jEff = NuiTooltip(jEff, JsonString(sTip));
    jRow = JsonArrayInsert(jRow, NuiWidth(jEff, LEGFEAT_COL_EFF));

    return NuiHeight(NuiRow(jRow), LEGFEAT_ROW_H);
}

json LegFeat_Window(object oPC)
{
    int nRemaining = LegFeat_Remaining(oPC);
    json jCol = JsonArray();

    string sHdr;
    if (nRemaining > 0)
        sHdr = "You may choose " + IntToString(nRemaining) + " legendary feat"
             + ((nRemaining == 1) ? "." : "s.");
    else
        // Kept short on purpose: it is concatenated with LEGFEAT_SUBTITLE and
        // the pair has to stay under LEGFEAT_HDR_WRAP_AT, or this one state
        // drops to the left-justified fallback while every other reads centred.
        sHdr = "Your legendary picks are all spent.";
    if (LEGFEAT_SUBTITLE != "")
        sHdr += "  " + LEGFEAT_SUBTITLE;

    if (GetStringLength(sHdr) <= LEGFEAT_HDR_WRAP_AT)
    {
        // The normal case: one centred line. A label cannot wrap, which is
        // exactly why the length is checked first.
        jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
            NuiLabel(JsonString(sHdr), JsonInt(NUI_HALIGN_CENTER),
                     JsonInt(NUI_VALIGN_MIDDLE)), LEGFEAT_LIST_W),
            LEGFEAT_HDR_H));
    }
    else
    {
        // Too long to fit centred on one line. Wrap it instead — borderless
        // text with no scrollbars, so it still reads as prose. It is
        // left-justified because NUI text takes no alignment; that is the price
        // of not clipping the sentence in half.
        jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
            NuiText(JsonString(sHdr), FALSE, NUI_SCROLLBARS_NONE),
            LEGFEAT_LIST_W), LEGFEAT_SUB_H));
    }

    // Explicitly sized, vertical scrollbars only: the list can grow to the whole
    // feat pool without the layout changing shape or scrolling sideways.
    json jList = JsonArray();
    int i;
    for (i = 0; i < LEGFEAT_COUNT; i++)
        jList = JsonArrayInsert(jList, LegFeat_Row(oPC, i, nRemaining));
    json jGroup = NuiGroup(NuiCol(jList), TRUE, NUI_SCROLLBARS_Y);
    jGroup = NuiWidth(jGroup, LEGFEAT_LIST_W);
    jGroup = NuiHeight(jGroup, LEGFEAT_LIST_H);
    jCol = JsonArrayInsert(jCol, jGroup);

    json jFoot = JsonArray();
    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiId(NuiButton(JsonString("Close")), "bclose"), 120.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    return NuiWindow(NuiCol(jCol), JsonString("Legendary Feats"),
        NuiRect(-1.0, -1.0, LEGFEAT_WIN_W, LEGFEAT_WIN_H),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

void LegFeat_Close(object oPC)
{
    int nTok = GetLocalInt(oPC, LEGFEAT_TOK);
    if (nTok) NuiDestroy(oPC, nTok);
    DeleteLocalInt(oPC, LEGFEAT_TOK);
}

// Open (or re-open) the picker. Destroys any stale instance first, so calling
// this after a pick is how the list refreshes.
void LegFeat_Open(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nOld = NuiFindWindow(oPC, LEGFEAT_WIN);
    if (nOld) NuiDestroy(oPC, nOld);

    int nTok = NuiCreate(oPC, LegFeat_Window(oPC), LEGFEAT_WIN, "legfeat_evt");
    SetLocalInt(oPC, LEGFEAT_TOK, nTok);
}
