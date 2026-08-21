// _spfailenter - OnEnter for the `spellfailarea` trigger: the Well of Eru's
// no-casting zone (100% arcane spell failure while you stand in it).
//
// THE APPLY IS DEFERRED, AND THAT IS THE POINT OF THIS REWRITE.
//
// The trigger's polygon covers the whole southern body of the Well - everything
// below y ~51 - and the rest-menu teleport lands the player on `secondchance`
// (24.95, 4.89), deep inside it, while every DOOR into the area arrives outside
// it (the Bree door at y 80, the buff-room transition at y 55). So a teleport
// fires this script in the same frame as the area load and a door arrival never
// does. That is exactly the asymmetry behind the report (roadmap
// bard-song-issues-round-2): teleport into the Well and every buff ICON
// disappears while the character sheet stays correctly buffed; walk in through a
// door or the pull chain and the icons survive.
//
// Applying an effect to a PC while the client is still building the character
// object for the newly loaded area leaves the client's effect-ICON list
// desynced: it keeps the effects, so the sheet and the combat log stay right,
// but the icons are gone and nothing resyncs them afterwards. Re-casting the
// buff cannot bring them back either, because the buff really is still running
// and its own "already applied" guard correctly refuses - only a rest or a death
// ends the effects for real. A short delay keeps the apply out of that window.
//
// Also fixed here: this used to apply an UNGUARDED PERMANENT effect on every
// entry, to every object. A player accumulated one 100% spell-failure effect per
// crossing - twice per trip on the legacy two-hop teleport, plus one more on
// every rest inside the zone (on_mod_rest.nss re-stamps it on REST_FINISHED) -
// and every NPC that wandered the hub got one too. _spfailexit removes them all
// on the way out, so the stack was invisible until something counted effects.
const float SPFAIL_APPLY_DELAY = 1.5;

void SpFail_Apply(object oPC)
{
    // Still in the zone? They may have walked back out inside the delay.
    if (!GetIsObjectValid(oPC) || !GetLocalInt(oPC, "SPFAIL_ZONE")) return;

    ApplyEffectToObject(DURATION_TYPE_PERMANENT, EffectSpellFailure(100), oPC);
}

void main()
{
    object oEntering = GetEnteringObject();
    if (!GetIsPC(oEntering)) return;

    // Already flagged: a second OnEnter without an intervening OnExit (the old
    // two-hop teleport did exactly this) must not stack a second effect.
    if (GetLocalInt(oEntering, "SPFAIL_ZONE")) return;

    SetLocalInt(oEntering, "SPFAIL_ZONE", 1);
    DelayCommand(SPFAIL_APPLY_DELAY, SpFail_Apply(oEntering));
}
