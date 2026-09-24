// jb_evt.nss - NUI event handler for the player jukebox's song browser.
// Registered per-window via the sEventScript arg of NuiCreate in jb_nui.
#include "jb_nui"
#include "color"

void main()
{
    if (NuiGetEventType() != "click") return;   // buttons send "click"

    object oPC   = NuiGetEventPlayer();
    object oArea = GetArea(oPC);
    string sElem = NuiGetEventElement();

    if (sElem == "bclose")
    {
        JB_NuiClose(oPC);
        return;
    }

    // Search. The term is read from the bind HERE rather than watched, so the
    // text field keeps keyboard focus while it is being typed - see the header
    // of jb_nui.nss. Any change to the filter resets to page one, because the
    // page the player was on almost certainly does not exist in the new list.
    if (sElem == "bfind")
    {
        int nTok = GetLocalInt(oPC, JB_NUI_TOK);
        string sQ = JsonGetString(NuiGetBind(oPC, nTok, JB_BIND_SEARCH));
        SetLocalString(oPC, JB_NUI_Q, sQ);
        SetLocalInt(oPC, JB_NUI_PG, 0);
        JB_NuiOpen(oPC);
        return;
    }

    if (sElem == "ball")
    {
        DeleteLocalString(oPC, JB_NUI_Q);
        SetLocalInt(oPC, JB_NUI_PG, 0);
        JB_NuiOpen(oPC);
        return;
    }

    if (sElem == "bprev")
    {
        SetLocalInt(oPC, JB_NUI_PG, GetLocalInt(oPC, JB_NUI_PG) - 1);
        JB_NuiOpen(oPC);
        return;
    }

    if (sElem == "bnext")
    {
        SetLocalInt(oPC, JB_NUI_PG, GetLocalInt(oPC, JB_NUI_PG) + 1);
        JB_NuiOpen(oPC);
        return;
    }

    if (sElem == "bstop")
    {
        JB_Stop(oArea);
        SendMessageToPC(oPC, ColorString(
            "[Jukebox] The music fades, and the room takes up its own again.",
            COLOR_LIGHT_BLUE));
        JB_NuiOpen(oPC);
        return;
    }

    // "p<catalogue index>" - play that track in this room.
    if (GetStringLeft(sElem, 1) != "p") return;
    int nIndex = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));
    if (nIndex < 0 || nIndex >= JB_CatCount()) return;

    // Re-derived here rather than trusted from the window: the row set the
    // player clicked is a snapshot, and someone else in the room may have
    // changed the music since it was drawn.
    int nRow = JB_CatRow(nIndex);
    if (nRow < 0) return;

    JB_StartRow(oArea, nRow);

    SendMessageToPC(oPC, ColorString(
        "[Jukebox] Now playing: " + JB_CatName(nIndex) + ".", COLOR_LIGHT_BLUE));

    // Rebuild so the row that is now playing greys out and the status line at
    // the top agrees with the room.
    JB_NuiOpen(oPC);
}
