// pl_thr_1m - rest-menu action (leader only): set the party's minimum item
// value to trigger a loot roll to 1000000 gp. Persisted on the leader.
#include "inc_partyloot"

void main()
{
    object oPC = GetPCSpeaker();
    SetCampaignInt(PL_DB, "threshold", 1000000, oPC);
    PL_BroadcastSettings(oPC);
}
