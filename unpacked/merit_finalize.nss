// merit_finalize — Reply action: commit the confirmed redemption.
// Instant rewards are granted on the spot; DM rewards become a pending request.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_pick_id");
    if (nId <= 0) return;
    if (GetLocalInt(oPC, "merit_pick_dm")) Merit_RequestById(oPC, nId);
    else                                   Merit_GrantInstant(oPC, nId);
}
