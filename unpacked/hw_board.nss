// hw_board - the Gourd Board (Well of Eru), OnUsed.
//
// During the event: hands in every Pumpkin Guts the PC carries and shows the
// standings. During the claim week (Nov 1-7): opens the hw_board conversation,
// where the PC picks one prize from their tier or any tier below it. The Bag of Pumpkin
// Seeds goes to anyone who has handed in at least one gut, once a year.
// Turn-in (takes items, gives nothing), seeds and claim (give, take nothing)
// are separate scripts so a reward and a take are never one code path.

#include "hw_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (HW_Phase() == HW_PHASE_CLAIM)
    {
        ExecuteScript("hw_board_seeds", oPC);
        int nTier = HW_ClaimTier(oPC);
        if (nTier == 0)
            SendMessageToPC(oPC, "The Gourd Board has no prize for you this year ("
                + IntToString(HW_GetGuts(oPC)) + " guts handed in).");
        else if (HW_Claimed(oPC))
            SendMessageToPC(oPC, "You have already claimed your Harvest of Shadows prize.");
        else
            ActionStartConversation(oPC, "hw_board", TRUE, FALSE);
    }
    else
    {
        ExecuteScript("hw_board_turn", oPC);
        ExecuteScript("hw_board_seeds", oPC);
    }
}
