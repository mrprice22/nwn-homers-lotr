// pl_thr_250k - rest-menu action (leader only): set the party's minimum item
// value to trigger a loot roll to 250000 gp. Persisted on the leader.
#include "inc_partyloot"

void main()
{
    object oPC = GetPCSpeaker();
    SetCampaignInt(PL_DB, "threshold", 250000, oPC);
    PL_BroadcastSettings(oPC);
}
