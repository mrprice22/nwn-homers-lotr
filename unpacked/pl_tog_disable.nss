// pl_tog_disable - rest-menu action (leader only): enable/disable party loot
// rolling for the whole party. Persisted on the leader in the campaign DB.
#include "inc_partyloot"

void main()
{
    object oPC = GetPCSpeaker();
    int bNow = !PL_IsDisabled(oPC);
    SetCampaignInt(PL_DB, "disabled", bNow, oPC);
    PL_BroadcastSettings(oPC);
}
