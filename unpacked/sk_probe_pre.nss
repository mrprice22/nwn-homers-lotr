// sk_probe_pre.nss -- NWNX_ON_LEVEL_UP_BEFORE handler for the spells-known probe.
// Snapshots known-spell counts so sk_probe_post.nss can diff them after the level.
// Subscribed in onmoduleload.nss. See sk_probe_inc.nss for why this exists.

#include "sk_probe_inc"

void main()
{
    SK_Snapshot(OBJECT_SELF);
}
