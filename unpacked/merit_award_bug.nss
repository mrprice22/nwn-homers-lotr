// merit_award_bug — Reply action: award a Defect Report merit to selected player.
#include "merit_db"
void main()
{
    object oDM    = GetPCSpeaker();
    string sCdKey = GetLocalString(oDM, "merit_sel_cdkey");
    string sName  = GetLocalString(oDM, "merit_sel_name");

    Merit_AwardBug(sCdKey);
    Merit_Ledger(sCdKey, sName, MERIT_BUG_VALUE, "award: defect report", 0);

    SendMessageToPC(oDM, "[Merit] Awarded Defect Report (+1) to " + sName + ".");

    // Notify the player if they are online.
    object oTarget = GetFirstPC();
    while (GetIsObjectValid(oTarget))
    {
        if (GetPCPublicCDKey(oTarget) == sCdKey)
        {
            SendMessageToPC(oTarget,
                "[Merit] A DM has logged your defect report. Thank you!");
            break;
        }
        oTarget = GetNextPC();
    }

    // Keep token fresh for the award sub-menu heading.
    SetCustomToken(5011, sName);
}
