// merit_award_uat - Reply action: award a UAT / validation merit to selected player.
//
// Unlike the other three award replies this is not tied to reporting an idea:
// it credits whoever helped VERIFY a fix. Several players can be credited for
// the same roadmap item, and none of them need be the one who reported it.
#include "merit_db"
void main()
{
    object oDM    = GetPCSpeaker();
    string sCdKey = GetLocalString(oDM, "merit_sel_cdkey");
    string sName  = GetLocalString(oDM, "merit_sel_name");

    Merit_AwardUat(sCdKey);
    Merit_Ledger(sCdKey, sName, MERIT_UAT_VALUE, "award: UAT validation", 0);

    SendMessageToPC(oDM, "[Merit] Awarded UAT Validation (+1) to " + sName + ".");

    // Notify the player if they are online.
    object oTarget = GetFirstPC();
    while (GetIsObjectValid(oTarget))
    {
        if (GetPCPublicCDKey(oTarget) == sCdKey)
        {
            SendMessageToPC(oTarget,
                "[Merit] A DM has credited you for helping test a fix. Thank you!");
            break;
        }
        oTarget = GetNextPC();
    }

    // Keep token fresh for the award sub-menu heading.
    SetCustomToken(5011, sName);
}
