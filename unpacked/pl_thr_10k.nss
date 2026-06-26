// pl_thr_10k — rest-menu action (leader only): set the party's minimum item
// value to trigger a loot roll to 10000 gp. Persisted on the leader.
#include "inc_partyloot"

void main()
{
    object oPC = GetPCSpeaker();
    SetCampaignInt(PL_DB, "threshold", 10000, oPC);
    PL_BroadcastSettings(oPC);
}
