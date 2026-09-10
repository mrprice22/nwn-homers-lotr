// cp_anntick -- Crash Party: the countdown firing itself.
//
// Scheduled by CP_AnnounceSchedule (cp_inc.nss). Fires the next line and queues
// the one after, so the whole countdown runs from a single manual press.
//
// Retires quietly if it has been superseded -- a manual press, or the master
// switch being thrown, bumps CP_ANN_GEN and this tick is no longer the newest.
// Without that, pressing the placard early would leave the old timer running and
// the next line would go out twice.
//
// No admin gate here on purpose: nobody invoked it, the schedule did. The gate
// lives on the manual path in cp_announce.nss.

#include "cp_inc"

void main()
{
    object oMod = GetModule();

    int nSeen = GetLocalInt(oMod, CP_ANN_SEEN) + 1;
    SetLocalInt(oMod, CP_ANN_SEEN, nSeen);
    if (nSeen < GetLocalInt(oMod, CP_ANN_GEN)) return;   // an older, retired timer

    CP_AnnounceFire();
    CP_AnnounceSchedule();
}
