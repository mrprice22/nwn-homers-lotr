// merit_award_exp - Reply action: award an Exploit Report merit to selected player.
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


    Merit_AwardExploit(sCdKey);
    Merit_Ledger(sCdKey, sName, MERIT_EXPLOIT_VALUE, "award: exploit report", 0);

    SendMessageToPC(oDM, "[Merit] Awarded Exploit Report (+3) to " + sName + ".");

    object oTarget = GetFirstPC();
    while (GetIsObjectValid(oTarget))
    {
        if (GetPCPublicCDKey(oTarget) == sCdKey)
        {
            SendMessageToPC(oTarget,
                "[Merit] A DM has logged your exploit report. Thank you!");
            break;
        }
        oTarget = GetNextPC();
    }

    SetCustomToken(5011, sName);
}
