// forge_fate_ctx.nss - action script on "Reforge the fate of ..." (Loot
// Overhaul Phase 7, lo-fate-token / lo-fate-ratchet), injected into the four
// Forge of Wonders smith dialogs by bin/inject_forge_disenchant.py.  Re-primes
// the anvil tokens (as forge_anvil_ctx does) and then the confirm line's own
// token LOOT_FATE_TOK (6121): what a reforge would change, what stays and the
// room fate has - or the refusal, before the PC breaks a Shard.  Custom tokens
// are server-global, so it must run right before the confirm entry renders.
#include "loot_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!ForgeRefreshAnvilContext(oPC))
    {
        SetCustomToken(LOOT_FATE_TOK, "Lay a single piece upon my anvil first, and I "
            + "will see what fate it might have had.");
        return;
    }
    SetCustomToken(LOOT_FATE_TOK, Loot_FateOutlook(GetLocalObject(oPC, "MODIFY_ITEM"),
        GetLocalInt(oPC, "MODIFY_MAX"), GetLocalInt(oPC, "MODIFY_MAX_PROPS"), oPC));
}
