// legfeat_disarm.nss - the fifth thing Legendary Juggernaut promises.
//
// Subscribed to NWNX_ON_DISARM_BEFORE in onmoduleload.nss, alongside
// disarm_catch (the module's weapon-recovery handler - NWNX_Events runs every
// subscriber, so the two do not collide). For this event OBJECT_SELF is the
// creature BEING disarmed.
//
// Knockdown, entangle, paralysis and slow are all IMMUNITY_TYPE_* values and
// are applied as ordinary immunity effects in LegFeat_ApplyOne. Disarm is not:
// the engine has no immunity type for it, so the only way to make a weapon
// unstrikable is to refuse the event before it resolves. That is what this
// does, and it is why Juggernaut is an EFFECT feat with one hook bolted on
// rather than a pure effect feat.
//
// Skipping BEFORE means disarm_catch's own BEFORE snapshot is harmless (it
// records the wielded weapon and does nothing else) and its AFTER never fires,
// because the disarm never happens.

#include "nwnx_events"
#include "legfeat_ids_inc"

void main()
{
    object oTarget = OBJECT_SELF;
    if (!GetHasFeat(FEAT_LEGENDARY_JUGGERNAUT, oTarget)) return;

    NWNX_Events_SkipEvent();

    if (GetIsPC(oTarget))
        SendMessageToPC(oTarget, "Legendary Juggernaut: your weapon cannot be "
                               + "struck from your hand.");
}
