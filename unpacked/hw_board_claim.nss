// hw_board_claim - hand over the prize the PC picked in hw_board.dlg
// (OBJECT_SELF = PC; the pick is in the "hw_pick" local, set by hw_claim_N).
//
// Everything is re-checked HERE, at grant time, never trusted from the
// conversation's conditionals: the phase, that the pick belongs to the PC's
// own tier, and the persistent claimed flag. Deliver first, then mark claimed,
// so a failed hand-over can be retried and a relog can never claim twice.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    string sRes = GetLocalString(oPC, "hw_pick");
    DeleteLocalString(oPC, "hw_pick");
    if (HW_Phase() != HW_PHASE_CLAIM) return;

    int nTier = HW_ClaimTier(oPC);
    if (nTier == 0 || HW_PrizeTier(sRes) != nTier) return;
    if (HW_Claimed(oPC))
    {
        SendMessageToPC(oPC, "You have already claimed your Harvest of Shadows prize.");
        return;
    }

    object oPrize = CreateItemOnObject(sRes, oPC);
    if (!GetIsObjectValid(oPrize))
    {
        SendMessageToPC(oPC, "The board could not hand over your prize - tell an admin.");
        return;
    }
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "UPDATE hw_guts SET claimed=@t WHERE year=@y AND ident=@i");
    SqlBindInt(q, "@t", nTier);
    SqlBindInt(q, "@y", HW_Year());
    SqlBindString(q, "@i", HW_Ident(oPC));
    SqlStep(q);
    SendMessageToPC(oPC, COLOR_ORANGE + "Harvest of Shadows: you finished rank "
        + IntToString(HW_Rank(oPC)) + " and claim " + GetName(oPrize) + "." + COLOR_END);
}
