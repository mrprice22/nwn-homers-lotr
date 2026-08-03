// cbd_death.nss — Combat Dummy OnDeath.
//
// TWO callers, and the difference is CBD_ACTIVE:
//
//   * the PLANNED death at the end of a full 10-round set (CBD_SelfDestruct in
//     cbd_inc). CBD_EndSession has already reported, recorded and cleared the
//     session, so the cancel branch below is skipped and all this does is stand
//     a fresh dummy back up — which is the whole point: the destruction visual
//     and this 6-second respawn ARE the end-of-set cue.
//
//   * an UNPLANNED death, which must never happen: cbd_damage zeroes all
//     incoming damage and cbd_spawn grants death immunity. If something gets
//     through anyway, the in-progress session is thrown away (NOT recorded — a
//     partial run is not a score) before the same respawn happens.

#include "cbd_inc"

void main()
{
    object oSelf = OBJECT_SELF;

    // Stale ticks from the dead dummy die with it, but bump the serial anyway
    // so nothing can fire into the replacement.
    if (GetLocalInt(oSelf, CBD_VAR_ACTIVE))
        CBD_CancelSession(oSelf, "The combat dummy was destroyed - the test is cancelled and nothing was recorded.");

    // Delayed commands assigned to a corpse are discarded when it decays, so
    // the respawn is assigned to the module — the same trick se_respawn_inc.nss
    // uses for static creatures.
    location lSpawn = GetLocalLocation(oSelf, CBD_VAR_SPAWN);
    if (!GetIsObjectValid(GetAreaFromLocation(lSpawn))) lSpawn = GetLocation(oSelf);

    AssignCommand(GetModule(), DelayCommand(6.0, CBD_Respawn(lSpawn)));
}
