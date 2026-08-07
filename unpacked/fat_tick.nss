// fat_tick - the soul-fatigue decay ticker, one running instance per PC that
// currently holds stacks (roadmap: heal-soul-fatigue-rebalance).
//
// Self-rescheduling loop in the module's usual shape (cf. _spfail_cycle.nss):
// armed by FAT_Kick(), guarded by the fat_ticking local, and it stops itself
// once the queue empties. It runs on the PC rather than the module ON PURPOSE
// - a logged-out PC's delayed commands never fire, which is precisely how
// soul-fatigue decay pauses while a character is offline.
//
// All the work is in fat_inc.nss; this file exists only because a
// self-rescheduling loop needs a script resref to call.

#include "fat_inc"

void main()
{
    FAT_Tick(OBJECT_SELF);
}
