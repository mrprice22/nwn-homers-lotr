// cbd_death.nss - Combat Dummy OnDeath.
//
// TWO callers, and the difference is CBD_ACTIVE:
//
//   * the PLANNED death at the end of a full 10-round set (CBD_SelfDestruct in
//     cbd_inc). CBD_EndSession has already reported, recorded and cleared the
//     session, so the cancel branch below is skipped and all this does is stand
//     a fresh dummy back up - which is the whole point: the destruction visual
//     and this 6-second respawn ARE the end-of-set cue.
//
//   * an UNPLANNED death, which must never happen: cbd_damage restores the hit
//     points on both sides of every packet, and cbd_spawn grants immunity to
//     death effects, to the states that make a creature helpless (a coup de
//     grace kills outright, around all of that) and to level and ability drain.
//     If something still gets through, the in-progress session is thrown away
//     (NOT recorded - a partial run is not a score) before the same respawn
//     happens, and the cancel message NAMES the killer and the weapon in its
//     hand: every one of those paths was found from a player report, so the
//     next one has to arrive already identified instead of as "it died again".

#include "cbd_inc"

void main()
{
    object oSelf = OBJECT_SELF;

    // Stale ticks from the dead dummy die with it, but bump the serial anyway
    // so nothing can fire into the replacement.
    if (GetLocalInt(oSelf, CBD_VAR_ACTIVE))
    {
        string sWho = "";
        object oKiller = GetLastKiller();
        if (GetIsObjectValid(oKiller))
        {
            sWho = " (killed by " + GetName(oKiller);
            object oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oKiller);
            if (GetIsObjectValid(oWeapon)) sWho += " with " + GetName(oWeapon);
            sWho += " - please report this)";
        }

        CBD_CancelSession(oSelf, "The combat dummy was destroyed - the test is " +
                                 "cancelled and nothing was recorded." + sWho);
    }

    // Delayed commands assigned to a corpse are discarded when it decays, so
    // the respawn is assigned to the module - the same trick se_respawn_inc.nss
    // uses for static creatures.
    location lSpawn = GetLocalLocation(oSelf, CBD_VAR_SPAWN);
    if (!GetIsObjectValid(GetAreaFromLocation(lSpawn))) lSpawn = GetLocation(oSelf);

    AssignCommand(GetModule(), DelayCommand(6.0, CBD_Respawn(lSpawn)));
}
