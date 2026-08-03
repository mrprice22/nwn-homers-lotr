// Forge Warden greeting gate: TRUE when the PC still carries illegal gear.
// Reads the cached verdict (FORGE_WARDEN_DIRTY) computed off the dialog hot path
// by the chunked Warden scan (ForgeBeginWardenScan / forge_scan_step). Must stay
// O(1): a full inventory scan inside a StartingConditional overflows the
// NWScript instruction cap for large inventories, and the failed conditional
// reads FALSE - which used to hide the release reply and trap cleaned-up players.
#include "forge_inc"

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "FORGE_WARDEN_DIRTY");
}
