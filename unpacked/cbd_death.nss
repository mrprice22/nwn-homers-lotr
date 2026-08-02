// cbd_death.nss — Combat Dummy OnDeath: the fallback that must never be needed.
//
// cbd_damage zeroes all incoming damage and cbd_spawn grants death immunity, so
// a dummy should be unkillable. If something gets through anyway, the rule is:
// the in-progress session is thrown away (NOT recorded — a partial run is not a
// score), and a fresh dummy stands back up where this one was.

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
