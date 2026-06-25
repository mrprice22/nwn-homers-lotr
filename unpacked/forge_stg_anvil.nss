// Staged anvil disenchant menu entry (D1) action: re-prime the property list,
// per-slot cues (tokens 6110-6117) and the running status header (token 6119) for
// the item on the anvil, starting a fresh plan whenever the menu opens on a
// different item. Kept as the D1 entry action as a self-heal and so the build gate
// can identify D1, but the inbound reply scripts (forge_stg_open, the slot toggles,
// the page-nav replies) do the same priming BEFORE this entry's text renders —
// an entry's Actions Taken runs after its own text, so it cannot prime in time.
#include "forge_inc"

void main()
{
    ForgeStageOpen(GetPCSpeaker());
}
