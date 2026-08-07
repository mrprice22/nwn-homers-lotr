// nui_wrap_inc.nss - word-wrap a string for a NUI widget that will not wrap it.
//
// WHY THIS EXISTS. NUI gives you three ways to show a string and none of them
// wraps where you need it to:
//
//   label    - aligns, never wraps. It CLIPS SILENTLY, so an over-long string
//              simply loses its tail with no visual cue at all. This is what
//              made the Legendary Feats header read "You may choose 2 leg".
//   text     - wraps, but takes no alignment, so it is always left-justified.
//   tooltip  - neither. It renders whatever it is given as ONE LINE, with no
//              width limit and no clipping, so a 300-character description
//              runs off the side of the screen and past both window and
//              viewport (roadmap legendary-nui-wrapping).
//
// A `text` widget solves the first case by itself. Nothing solves the tooltip
// case except putting the line breaks in the string before handing it over,
// which is what this include is for.
//
// ASCII ONLY, deliberately. A non-ASCII byte in a .nss is a recorded trap in
// this repo (tests/check_legendary_feats.py gates the generated feat include on
// it), so there is no ellipsis character and no typographic dash below - "..."
// is three periods if a caller ever wants one.
//
// No `&` reference parameters: nw_inc_nui has none and neither does this, so it
// composes with the picker windows that include it.

// Default line budget in CHARACTERS, not pixels. It is an estimate against a
// proportional font and is deliberately conservative: a player running a larger
// UI scale fits fewer characters per line than you do. Same reasoning as
// LEGFEAT_HDR_WRAP_AT in legfeat_nui.nss, and a tighter number because a
// tooltip is a floating box rather than a sized widget.
const int NUI_WRAP_COLS = 60;

// Wrap ONE line - a string already known to hold no newline - to nCols
// characters, breaking only at spaces. Greedy: each output line takes as many
// whole words as fit.
//
// A single word longer than nCols is left intact on a line of its own rather
// than split mid-word, because the strings this handles are prose and a broken
// word reads worse than a slightly long line.
//
// Runs of spaces collapse to one. That is a visible change to strings like
// "...outright.  (Requires: ...)" which use a double space as a separator, and
// it is intended - a line break is doing that separator's job now.
string NuiWrapLine(string sLine, int nCols);

// Wrap sText to nCols characters. Newlines already in the string are PRESERVED
// as hard breaks and each of the lines between them is wrapped independently,
// so a TLK description that arrives pre-formatted keeps its paragraphs instead
// of being reflowed into one block. "\r\n" is handled as well as "\n".
string NuiWrapText(string sText, int nCols);

string NuiWrapLine(string sLine, int nCols)
{
    if (nCols <= 0) return sLine;
    if (GetStringLength(sLine) <= nCols) return sLine;

    string sOut  = "";   // finished lines, joined with "\n"
    string sCur  = "";   // the line being filled
    string sRest = sLine;

    while (sRest != "")
    {
        // Pull the next word off the front of what is left.
        string sWord;
        int nSp = FindSubString(sRest, " ");
        if (nSp < 0)
        {
            sWord = sRest;
            sRest = "";
        }
        else
        {
            sWord = GetSubString(sRest, 0, nSp);
            sRest = GetSubString(sRest, nSp + 1, GetStringLength(sRest) - nSp - 1);
        }

        if (sWord == "") continue;   // a run of spaces

        if (sCur == "")
            sCur = sWord;            // always take the first word, however long
        else if (GetStringLength(sCur) + 1 + GetStringLength(sWord) <= nCols)
            sCur += " " + sWord;
        else
        {
            sOut += ((sOut == "") ? "" : "\n") + sCur;
            sCur = sWord;
        }
    }

    if (sCur != "") sOut += ((sOut == "") ? "" : "\n") + sCur;
    return sOut;
}

string NuiWrapText(string sText, int nCols)
{
    if (nCols <= 0) return sText;

    // Fast path: no hard breaks to preserve.
    if (FindSubString(sText, "\n") < 0) return NuiWrapLine(sText, nCols);

    string sOut  = "";
    string sRest = sText;
    int bFirst = TRUE;

    while (TRUE)
    {
        string sPara;
        int nNl = FindSubString(sRest, "\n");
        if (nNl < 0)
        {
            sPara = sRest;
            sRest = "";
        }
        else
        {
            sPara = GetSubString(sRest, 0, nNl);
            sRest = GetSubString(sRest, nNl + 1, GetStringLength(sRest) - nNl - 1);
        }

        // A "\r\n" source would otherwise leave the CR glued to the last word,
        // inflating its measured length and printing as a stray glyph.
        int nPara = GetStringLength(sPara);
        if (nPara > 0 && GetSubString(sPara, nPara - 1, 1) == "\r")
            sPara = GetSubString(sPara, 0, nPara - 1);

        if (!bFirst) sOut += "\n";
        sOut += NuiWrapLine(sPara, nCols);
        bFirst = FALSE;

        if (nNl < 0) break;
    }

    return sOut;
}
