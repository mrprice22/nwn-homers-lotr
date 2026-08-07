// legfeat_nui.nss - the Legendary Feats picker window.
//
// Opened at character level 60 (legfeat_lvl, from NWNX_ON_LEVEL_UP_AFTER) and
// re-opened by finishing a rest while picks remain (on_mod_rest). Event handling
// is in legfeat_evt.nss, registered per-window via NuiCreate's sEventScript.
//
// WHY A CUSTOM PICKER. The engine's own level-up feat page hands out exactly one
// general feat at 60 to everybody, so the 1 / 2 / 3 allotment cannot be
// expressed to it - and legendary feats are deliberately invisible to it
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
// precedent - one group, explicit NuiHeight. The row widths below sum to less
// than LEGFEAT_LIST_W, and the group scrolls vertically only, so no amount of
// content can reintroduce a horizontal scrollbar.
//
// WHERE LONG TEXT MAY AND MAY NOT GO. NUI's three ways of showing a string each
// fail differently, and roadmap legendary-nui-wrapping was two of those failures
// reported as one defect:
//
//   label    - aligns, never wraps. CLIPS SILENTLY, no visual cue at all. This
//              is what made the header read "You may choose 2 leg" and what was
//              cutting the effect column off mid-sentence.
//   text     - wraps, honours "\n", scrolls. Takes no alignment.
//   tooltip  - neither wraps NOR clips: it draws one line as wide as it likes,
//              straight off the edge of the screen. AND IT STRIPS NEWLINES, so
//              it cannot be pre-wrapped either - that was tried first, shipped,
//              and came back unchanged from in-game testing.
//
// Therefore: every string in this window that can exceed its space is a sized
// `text` widget - the effect column and the detail pane. Tooltips carry only
// short bounded strings. A long string must never be attached to a tooltip
// again, and there is no wrapper that would make it safe to.

#include "nw_inc_nui"
#include "legfeat_inc"

const string LEGFEAT_WIN = "legfeats";     // NuiCreate window id
const string LEGFEAT_TOK = "LEGFEAT_TOK";  // PC local: this window's token
// PC local: which row the detail pane is showing, stored +1 so that row 0 is
// distinguishable from "nothing selected yet". Same convention as CSP_SEL in
// csp_nui.nss.
const string LEGFEAT_SEL = "LEGFEAT_SEL";
// The detail pane's contents are BOUND, not baked into the layout, so that
// clicking "?" can update it without rebuilding the window. Rebuilding threw
// away the list's scroll position - sometimes to the top, sometimes to wherever
// the client had last cached it - which made the button feel like it was
// yanking the list around. The bind is the whole reason the pane is not just
// another JsonString in LegFeat_Window.
const string LEGFEAT_BIND_DTL = "lf_detail";

// The one line of tunable text under the "you may choose N" header. It exists
// because where a player re-picks is not settled - the re-pick node is parked on
// Ping Pong and will likely move - and the window should not have to be edited
// when it does. Set it to "" to drop the line entirely.
//
// It is appended to the "You may choose N legendary feats." header and shown on
// the SAME centred line, wrapping onto a second line only if the two together
// are too long - see LEGFEAT_HDR_WRAP_AT below for what that costs.
//
// BUDGET: header + subtitle together should stay under ~80 characters. See
// README.md "Tuning the picker's subtitle".
const string LEGFEAT_SUBTITLE = "Can repick with Ping Pong in Well of Eru";

// Where the header stops being one line.
//
// NUI forces a choice: a `label` centres but NEVER wraps (it clips silently -
// that is how the header once read "You may choose 2 leg"), while `text` wraps
// but cannot be aligned, so it is always left-justified. There is no centred
// wrapping control.
//
// So: at or under this many characters the header and subtitle share one centred
// label, which is the normal case and the one that looks right. Over it, they
// fall back to a two-line wrapping text box - left-justified, but readable,
// which beats clipping half the sentence. Keep the subtitle short and the
// fallback never fires.
//
// The threshold is characters against a proportional font, so it is an estimate,
// deliberately conservative: a player running a larger UI scale fits fewer
// characters per line than you do.
const int LEGFEAT_HDR_WRAP_AT = 80;

// Geometry. The four row columns sum to 660 (80 + 40 + 200 + 340), comfortably
// inside the list group's 680, which is what keeps the horizontal scrollbar
// away. Keep that sum under LEGFEAT_LIST_W if you retune any of them.
//
// The name column gave 40 of its width to the effect column: the longest feat
// name is 22 characters and fits 200 easily, while the longest effect string is
// 62 and was being cut off at 340. The row is tall enough for the effect to
// take two lines, which is what that string needs.
const float LEGFEAT_WIN_W   = 720.0;
const float LEGFEAT_WIN_H   = 570.0;
const float LEGFEAT_LIST_W  = 680.0;
const float LEGFEAT_LIST_H  = 300.0;
const float LEGFEAT_COL_BTN = 80.0;
const float LEGFEAT_COL_INFO = 40.0;   // the "?" detail button
const float LEGFEAT_COL_NAME = 200.0;
const float LEGFEAT_COL_EFF  = 340.0;
const float LEGFEAT_ROW_H    = 46.0;   // two lines of wrapped effect text
const float LEGFEAT_HDR_H    = 26.0;   // one centred line
const float LEGFEAT_SUB_H    = 40.0;   // two lines, wrapped fallback
// The detail pane. Sized for the worst case it has to hold - the 263-character
// description plus a three-clause measured requirement, about seven lines at
// this width - and given an automatic scrollbar anyway, because it is the one
// surface in the window that MUST NOT lose text: there is nowhere left to put
// what it drops.
const float LEGFEAT_DTL_H    = 130.0;

json LegFeat_Window(object oPC);
void LegFeat_Open(object oPC);
void LegFeat_Close(object oPC);

// Which row the detail pane is showing, or -1 for none.
int LegFeat_Selected(object oPC)
{
    int nSel = GetLocalInt(oPC, LEGFEAT_SEL) - 1;
    if (nSel < 0 || nSel >= LEGFEAT_COUNT) return -1;
    return nSel;
}

// Select a row into the detail pane.
void LegFeat_Select(object oPC, int nIndex)
{
    if (nIndex < 0 || nIndex >= LEGFEAT_COUNT) DeleteLocalInt(oPC, LEGFEAT_SEL);
    else SetLocalInt(oPC, LEGFEAT_SEL, nIndex + 1);
}

// Push the currently selected row's text into the open window's detail pane.
//
// This is the ONLY thing a "?" click does - the window is deliberately NOT
// rebuilt. Rebuilding it lost the list's scroll position, and the client's own
// cache made that inconsistent: some clicks landed back at the top of the pool,
// some at the last remembered offset. Updating one bind leaves the list exactly
// where the player left it.
void LegFeat_RefreshDetail(object oPC);

// The full text of one feat, for the detail pane: name, description, and the
// measured requirement clause by clause.
//
// This is where the long strings ended up once it turned out a tooltip strips
// newlines and refuses to wrap. A `text` widget honours both, so this one is
// free to use "\n" and to run as long as it needs to.
string LegFeat_DetailText(object oPC, int nIndex)
{
    if (nIndex < 0)
        return "Click the \"?\" beside a feat to read what it does and exactly "
             + "what it requires.";

    string sOut = LegFeat_NameAt(nIndex) + "\n" + LegFeat_DescAt(nIndex);

    // MEASURED, not just stated: "BAB 35+ (you have 34) [X], Epic Prowess [ok]"
    // rather than "BAB 35+, Epic Prowess". A multi-clause requirement rendered
    // as one flat string cannot say which half failed, and a player reads the
    // half they can check - which is how a character with a qualifying BAB and
    // no Epic Prowess came to report that 35 was being rejected (roadmap
    // legendary-feat-prereq-defect-1).
    //
    // Shown whether or not it is met, because a player deciding how to spend two
    // picks needs to see that Onslaught wants Assault BEFORE taking something
    // else.
    string sPrereq = LegFeat_PrereqStatusAt(oPC, nIndex);
    if (sPrereq != "") sOut += "\nRequires: " + sPrereq;

    if (LegFeat_HasPick(oPC, LegFeat_IdAt(nIndex)))
        sOut += "\nYou have taken this feat.";

    return sOut;
}

// One list entry: either a "Take" button (id "t<index>") or, once taken, a
// plain line saying so.
json LegFeat_Row(object oPC, int nIndex, int nRemaining)
{
    int nFeatId = LegFeat_IdAt(nIndex);
    int bTaken  = LegFeat_HasPick(oPC, nFeatId);
    int bQualified = LegFeat_MeetsPrereq(oPC, nIndex);

    // NOTHING LONG GOES IN A TOOLTIP. A NUI tooltip renders its string as one
    // line, never clips it, and - measured in game, which is the only way to
    // find this out - SILENTLY STRIPS ANY NEWLINE YOU PUT IN IT. So it cannot
    // be wrapped, cannot be broken up, and cannot be relied on for anything
    // longer than fits across the screen at whatever position it pops up.
    //
    // The first attempt at roadmap legendary-nui-wrapping pre-wrapped the
    // string; the breaks were discarded and the tooltip drew exactly as wide as
    // before. The full description and the measured requirement list live in the
    // detail pane instead (LegFeat_Detail below), and the tooltip is reduced to
    // the same short line the row already shows - which cannot overflow, because
    // it is bounded by the same 62-character worst case the effect column is.
    string sEff = LegFeat_EffectAt(nIndex);
    if (!bTaken && !bQualified)
        // An unqualified row shows what it wants instead of what it gives: the
        // effect is moot until the prerequisite is met, and "Needs: ..." in the
        // column the eye is already on beats a detail pane nobody opened.
        //
        // ONE clause - the first unmet one, with the player's own value - not
        // the whole requirement, which would make the row several lines tall for
        // the three-clause feats. The full list is one "?" click away.
        sEff = "Needs: " + LegFeat_FirstUnmetAt(oPC, nIndex);

    string sTip = sEff;

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
        // and decide before spending. LegFeat_Take re-checks the prerequisite -
        // this window is only a snapshot of it.
        jBtn = NuiEnabled(jBtn, JsonBool(nRemaining > 0 && bQualified));
        jBtn = NuiTooltip(jBtn, JsonString(sTip));
        jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, LEGFEAT_COL_BTN));
    }

    // The "?" button (id "i<index>") - the only way to read a full description
    // now that a tooltip cannot hold one. It selects this row into the detail
    // pane below the list, and it is deliberately ALWAYS enabled: a player most
    // needs to read what a feat does when the row is greyed out and they are
    // deciding whether it is worth qualifying for.
    json jInfo = NuiId(NuiButton(JsonString("?")), "i" + IntToString(nIndex));
    jInfo = NuiTooltip(jInfo, JsonString("Show the full description below"));
    jRow = JsonArrayInsert(jRow, NuiWidth(jInfo, LEGFEAT_COL_INFO));

    // Name and a short effect summary. The full description is in the detail
    // pane - an inline description is what forced the horizontal scrollbar.
    json jName = NuiLabel(JsonString(LegFeat_NameAt(nIndex)),
                          JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jName = NuiTooltip(jName, JsonString(sTip));
    jRow = JsonArrayInsert(jRow, NuiWidth(jName, LEGFEAT_COL_NAME));

    // A `text` widget, NOT a label: this is the one column whose contents can
    // outrun their width, and a label answers that by dropping the tail with no
    // visual cue - "-3 target AC per hit, stacks 3, capped at its armour+shield
    // AC" is 62 characters and was arriving as roughly two thirds of a sentence
    // (roadmap legendary-nui-wrapping). Borderless with no scrollbar so it still
    // reads as a table cell rather than a box; LEGFEAT_ROW_H is what guarantees
    // the second line has somewhere to go, since NUI_SCROLLBARS_NONE means
    // anything past the box height would be clipped instead.
    //
    // The price is alignment: NUI text takes none, so this column no longer
    // sits vertically centred against the button and the name. That is the same
    // trade the header makes above, and it is the right way round - a
    // misaligned sentence still reads, a truncated one does not.
    json jEff = NuiText(JsonString(sEff), FALSE, NUI_SCROLLBARS_NONE);
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
        // Too long to fit centred on one line. Wrap it instead - borderless
        // text with no scrollbars, so it still reads as prose. It is
        // left-justified because NUI text takes no alignment; that is the price
        // of not clipping the sentence in half.
        jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
            NuiText(JsonString(sHdr), FALSE, NUI_SCROLLBARS_NONE),
            LEGFEAT_LIST_W), LEGFEAT_SUB_H));
    }

    // Explicitly sized, vertical scrollbars only: the list can grow to the whole
    // feat pool without the layout changing shape or scrolling sideways. The
    // whole pool already overflows it - 18 rows at LEGFEAT_ROW_H is well past
    // LEGFEAT_LIST_H - which is what the vertical scrollbar is for; the group
    // and window heights are sized for how many rows land on screen at once,
    // not to fit them all.
    json jList = JsonArray();
    int i;
    for (i = 0; i < LEGFEAT_COUNT; i++)
        jList = JsonArrayInsert(jList, LegFeat_Row(oPC, i, nRemaining));
    json jGroup = NuiGroup(NuiCol(jList), TRUE, NUI_SCROLLBARS_Y);
    jGroup = NuiWidth(jGroup, LEGFEAT_LIST_W);
    jGroup = NuiHeight(jGroup, LEGFEAT_LIST_H);
    jCol = JsonArrayInsert(jCol, jGroup);

    // The detail pane. Bordered, so it reads as a panel rather than as another
    // row, and NUI_SCROLLBARS_AUTO rather than NONE: this is the only place the
    // full description exists, so if it ever outgrows LEGFEAT_DTL_H the player
    // must be able to scroll to the rest instead of silently losing it.
    json jDetail = NuiText(NuiBind(LEGFEAT_BIND_DTL), TRUE, NUI_SCROLLBARS_AUTO);
    jDetail = NuiWidth(jDetail, LEGFEAT_LIST_W);
    jDetail = NuiHeight(jDetail, LEGFEAT_DTL_H);
    jCol = JsonArrayInsert(jCol, jDetail);

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
    // The detail pane starts empty next time rather than on whatever row was
    // last inspected, possibly several level-ups ago.
    DeleteLocalInt(oPC, LEGFEAT_SEL);
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

    // A bound widget starts empty until something writes to it, so seed the
    // pane here. That also means a rebuild after taking a feat comes back
    // showing whatever the player was reading, rather than blank.
    LegFeat_RefreshDetail(oPC);
}

void LegFeat_RefreshDetail(object oPC)
{
    int nTok = GetLocalInt(oPC, LEGFEAT_TOK);
    if (!nTok) return;
    NuiSetBind(oPC, nTok, LEGFEAT_BIND_DTL,
        JsonString(LegFeat_DetailText(oPC, LegFeat_Selected(oPC))));
}
