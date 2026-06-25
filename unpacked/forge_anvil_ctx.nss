// Action script on the forge "modify the item" / "strip enchantments" reply:
// re-derive the item on the anvil and re-prime every display token RIGHT BEFORE
// the next NPC line shows it. NWN custom tokens are server-global and the modify
// path used to set none of them, so the confirm/cost lines could render the last
// item any player worked (the "speaks about the last weapon" bug) and a stale or
// "no" GP cap. Mirrors the isitemonanvil reply-gate. Supersedes forge_id (which
// only re-identified the item).
#include "forge_inc"

void main()
{
    ForgeRefreshAnvilContext(GetPCSpeaker());
}
