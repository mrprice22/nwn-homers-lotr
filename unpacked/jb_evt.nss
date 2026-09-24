// jb_evt.nss - NUI event handler for the player jukebox's song browser.
// Registered per-window via the sEventScript arg of NuiCreate in jb_nui.
#include "jb_nui"

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
    // of jb_nui.nss. Any change to the filter or the sort resets to page one,
    // because the page the player was on almost certainly does not exist in the
    // new list.
    if (sElem == "bfind")
    {
        int nTok = GetLocalInt(oPC, JB_NUI_TOK);
        SetLocalString(oPC, JB_NUI_Q,
            JsonGetString(NuiGetBind(oPC, nTok, JB_BIND_SEARCH)));
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

    if (sElem == "bsort")
    {
        SetLocalString(oPC, JB_NUI_SORT,
                       JB_Sort(oPC) == "plays" ? "" : "plays");
        SetLocalInt(oPC, JB_NUI_PG, 0);
        JB_NuiOpen(oPC);
        return;
    }

    // Cycle the priority tier. One button rather than a control per tier per
    // row; the choice is made once and then spent.
    if (sElem == "btier")
    {
        int nTier = JB_Tier(oPC) + 1;
        if (nTier > JB_TIER_MAX) nTier = 0;
        SetLocalInt(oPC, JB_NUI_TIER, nTier);
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

    // "q<raw 2DA row>" - pay for it and put it in the queue.
    if (GetStringLeft(sElem, 1) != "q") return;
    int nRow = StringToInt(GetSubString(sElem, 1, GetStringLength(sElem) - 1));
    int nCat = JB_CatIndexForRow(nRow);
    if (nCat < 0) return;

    int nTier = JB_Tier(oPC);
    int nCost = JB_TierCost(nTier);

    // THE GOLD IS RE-CHECKED HERE, not trusted from the window. The greyed
    // button is a snapshot taken when the list was drawn, and the player may
    // have spent since - the same rule legfeat_nui states for its prerequisites
    // (legfeat_nui.nss:238) and brc_wheel has taken bets under since long
    // before that.
    if (GetGold(oPC) < nCost)
    {
        SendMessageToPC(oPC, ColorString(
            "[Jukebox] That costs " + JB_Gold(nCost) + " gp and you have "
            + JB_Gold(GetGold(oPC)) + ".", COLOR_LIGHT_BLUE));
        JB_NuiOpen(oPC);
        return;
    }

    TakeGoldFromCreature(nCost, oPC, TRUE);
    JB_Enqueue(oArea, nRow, JB_CatDuration(nCat), nTier, nCost, oPC);

    // Settle immediately: if the room was silent this starts the song now,
    // otherwise it simply leaves it in the queue behind whatever is playing.
    JB_Reconcile(oArea);

    if (GetLocalInt(oArea, JB_ROW) == nRow)
        SendMessageToPC(oPC, ColorString(
            "[Jukebox] " + JB_CatName(nCat) + ", playing now. "
            + JB_Gold(nCost) + " gp.", COLOR_LIGHT_BLUE));
    else
    {
        int nAhead = JB_AheadOf(oArea, nTier);
        SendMessageToPC(oPC, ColorString(
            "[Jukebox] " + JB_CatName(nCat) + " is in the queue for "
            + JB_Gold(nCost) + " gp, behind " + IntToString(nAhead + 1)
            + ((nAhead == 0) ? " song." : " songs."), COLOR_LIGHT_BLUE));
    }

    // Rebuild so the purse, the queue length and the playing row all agree with
    // what just happened.
    JB_NuiOpen(oPC);
}
