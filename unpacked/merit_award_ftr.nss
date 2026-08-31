// merit_award_ftr - Reply action: award a Feature Implementation merit to selected player.
#include "merit_db"
#include "admin_db"
void main()
{
    object oDM    = GetPCSpeaker();
    string sCdKey = GetLocalString(oDM, "merit_sel_cdkey");
    string sName  = GetLocalString(oDM, "merit_sel_name");

    // Authoritative half of the merit gate. The _cdkeymerit conditional on the
    // EmoteWand link only hides the menu line; this is what actually refuses.
    if (!Admin_CanMerit(oDM))
    {
        SendMessageToPC(oDM, "[Merit] You are not authorised to do that.");
        return;
    }


    Merit_AwardFeature(sCdKey);
    Merit_Ledger(sCdKey, sName, MERIT_FEATURE_VALUE, "award: feature implementation", 0);

    SendMessageToPC(oDM, "[Merit] Awarded Feature Implementation (+2) to " + sName + ".");

    object oTarget = GetFirstPC();
    while (GetIsObjectValid(oTarget))
    {
        if (GetPCPublicCDKey(oTarget) == sCdKey)
        {
            SendMessageToPC(oTarget,
                "[Merit] A DM has logged your feature contribution. Thank you!");
            break;
        }
        oTarget = GetNextPC();
    }

    SetCustomToken(5011, sName);
}
