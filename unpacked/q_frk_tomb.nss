// The Forbidden Realms (roadmap: forbidden-realms-key-tier)
// Tombs of the Lost Souls (gravesofthelostk) OnEnter wrapper: keep the area's
// original OnEnter (leash_to_area -- anti-kiting), then advance the journal for
// the arriving player, stand the return gate back up, and re-form the
// barrow-court if it is not currently standing.
#include "q_frk_inc"

void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);

    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;

    FRK_OnTombEntered(oPC);
    FRK_SpawnGate(FRK_WP_TOMB, FRK_WP_GATE);   // way back out
    FRK_SpawnCourt(OBJECT_SELF);
}
