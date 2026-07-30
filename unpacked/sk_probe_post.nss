// sk_probe_post.nss -- NWNX_ON_LEVEL_UP_AFTER handler for the spells-known probe.
// Diffs against sk_probe_pre.nss's snapshot and reports what the native level-up
// GUI actually granted. Subscribed in onmoduleload.nss alongside nextlvl_evt,
// which is subscribed to the same event -- NWNX_Events runs every subscriber.
// See sk_probe_inc.nss for why this exists and when to delete it.

#include "sk_probe_inc"

void main()
{
    SK_ReportDelta(OBJECT_SELF);
}
