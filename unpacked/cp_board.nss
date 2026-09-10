// cp_board -- Crash Party: the scoreboard placeable in the Well of Eru.
//
// OnUsed. Anyone may read it -- this one is for the players, not the DM.
//
// Shows the three things that actually drive a concurrency record: how many are
// on right now, what the number to beat is, and who is winning the drinking
// contest. The whole reason this exists is that a visible target is worth more to
// a record attempt than any single chaos item.

#include "cp_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nNow  = CP_OnlineCount();
    int nPeak = CP_GetPeak();
    if (nPeak <= 0) nPeak = 8;

    string sMsg = COLOR_YELLOW + "-- THE ROLL OF THE REVELLERS --" + COLOR_END + "\n";
    sMsg += "Players online right now: " + IntToString(nNow) + "\n";

    if (nNow > nPeak)
        sMsg += "Record to beat: " + IntToString(nPeak) + "  -- BEATEN! Hold it!\n";
    else if (nNow == nPeak)
        sMsg += "Record to beat: " + IntToString(nPeak) + "  -- TIED! One more!\n";
    else
        sMsg += "Record to beat: " + IntToString(nPeak) + "  (need "
             + IntToString(nPeak - nNow + 1) + " more)\n";

    string sTop = CP_TopSips(5);
    sMsg += "\n" + COLOR_YELLOW + "Deepest drinkers:" + COLOR_END + "\n";
    sMsg += (sTop == "") ? "Nobody has touched a drop yet.\n" : sTop;

    int nMine = CP_GetSips(oPC);
    if (nMine > 0) sMsg += "\nYour sips: " + IntToString(nMine);

    SendMessageToPC(oPC, sMsg);
}
