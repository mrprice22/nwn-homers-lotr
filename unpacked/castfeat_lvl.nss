// castfeat_lvl.nss - NWNX_ON_LEVEL_UP_AFTER handler for the caster feat
// proxies. Subscribed in onmoduleload.nss. See castfeat_inc.nss.
//
// _AFTER, not _BEFORE: the pick has to be on the character before there is
// anything to pair.

#include "castfeat_inc"

void main()
{
    CastFeat_Resolve(OBJECT_SELF);
}
