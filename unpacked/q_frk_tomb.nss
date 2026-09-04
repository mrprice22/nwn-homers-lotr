// The Forbidden Realms (roadmap: forbidden-realms-key-tier)
// Tombs of the Lost Souls (gravesofthelostk) OnEnter wrapper: keep the area's
// original OnEnter (leash_to_area -- anti-kiting), then advance the journal for
// the arriving player and stand the return gate back up.
//
// It no longer re-forms the barrow-court. The court moved out of the tombs and
// into area028, "Weather Top's Hidden Court", which the admin built in the
// toolset on 2026-09-04 -- so FRK_SpawnCourt is gone from q_frk_inc and there
// is nothing here to spawn. This area keeps its journal entry and its way back
// out; the fight is on the hill now.
#include "q_frk_inc"

void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);

    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;

    FRK_OnTombEntered(oPC);
    FRK_SpawnGate(FRK_WP_TOMB, FRK_WP_GATE);   // way back out
}
