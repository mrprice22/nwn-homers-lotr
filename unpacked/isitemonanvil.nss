// Reply gate for the forge menu: TRUE when exactly one item sits on the nearest
// pAnvilOfWonder. Delegates to ForgeRefreshAnvilContext (forge_inc), which is the
// single source of truth for "the item on the anvil" — it caches MODIFY_ITEM and
// primes every display token (name/base/worth/cap/headroom) and the PC caps. The
// modify/strip reply scripts call the same helper so the smith never speaks about
// a previously-worked item or quotes a stale cap.
#include "forge_inc"

int StartingConditional()
{
    return ForgeRefreshAnvilContext(GetPCSpeaker());
}
