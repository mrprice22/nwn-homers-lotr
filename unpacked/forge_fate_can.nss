// forge_fate_can.nss - reply gate for "Reforge the fate of ..." (Loot Overhaul
// Phase 7, lo-fate-token), injected into the four Forge of Wonders smith
// dialogs by bin/inject_forge_disenchant.py.  Shown when exactly one item sits
// on the anvil (ForgeRefreshAnvilContext, which also primes <CUSTOM100> and the
// MODIFY_MAX / MODIFY_MAX_PROPS caps) AND the PC carries a Shard of Fate.  It
// does not judge the item: forge_fate_go explains a refusal and keeps the Shard.
#include "loot_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetIsObjectValid(Loot_FindShard(oPC)) && ForgeRefreshAnvilContext(oPC);
}
