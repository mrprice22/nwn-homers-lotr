// hw_board_turn - hand in every Pumpkin Guts in the pack (OBJECT_SELF = PC).
//
// The count lives in halloweendb, not on the item, so guts may be traded and
// pooled freely until they are handed in - and only once.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    int nIn = 0;
    if (HW_Phase() == HW_PHASE_ACTIVE)
    {
        object oItem = GetFirstItemInInventory(oPC);
        while (GetIsObjectValid(oItem))
        {
            if (GetTag(oItem) == "hw_guts")
            {
                nIn += GetItemStackSize(oItem);
                DestroyObject(oItem);
            }
            oItem = GetNextItemInInventory(oPC);
        }
    }

    int nTotal = (nIn > 0) ? HW_AddGuts(oPC, nIn) : HW_GetGuts(oPC);
    string sMsg = COLOR_ORANGE + "-- THE GOURD BOARD --" + COLOR_END + "\n";
    if (nIn > 0)
        sMsg += "You hand over " + IntToString(nIn) + " Pumpkin Guts.\n";
    string sTop = HW_TopGuts(10);
    sMsg += (sTop == "") ? "No guts handed in yet this year.\n" : sTop;
    if (nTotal > 0)
        sMsg += "\nYour total: " + IntToString(nTotal) + " (rank "
              + IntToString(HW_Rank(oPC)) + ")";
    sMsg += "\nPrizes Nov 1-7 at this board - pick one from your tier or any tier below: ranks 1-3 "
          + "Harvest Lord, ranks 4-10 Harvest Reaper, anyone with " + IntToString(HW_TIER3_MIN_GUTS)
          + "+ guts Harvester. Everyone who hands in a gut gets a Bag of Pumpkin Seeds.";
    SendMessageToPC(oPC, sMsg);
}
