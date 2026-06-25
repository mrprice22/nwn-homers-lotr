// Action script for the replies that OPEN the staged disenchant menu (the
// "Strip enchantments..." hook and the confirm screen's "No, let me reconsider").
// Primes the per-slot cues (tokens 6110-6117) and the running status header
// (token 6119) for the item on the anvil RIGHT BEFORE the D1 menu entry renders.
// A reply's Actions Taken runs before its destination entry's text, so this is
// the correct place to set the tokens — the D1 entry's own action runs too late
// (which left token 6119 as "<UNRECOGNIZED TOKEN>" on first open).
#include "forge_inc"

void main()
{
    ForgeStageOpen(GetPCSpeaker());
}
