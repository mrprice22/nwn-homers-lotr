// chest_settibelt.nss -- OnOpen of SettiBeltChest (Numenor: Noirinan).
// Mint one end-game belt, but at most once per cooldown per chest: while the
// chest is spent-and-cooling it opens empty (no loot, and it is left unlocked so
// no key/pick is wasted). q_frk_enter re-locks it once the cooldown elapses.
// See setti_loot_inc.nss and the numenor-chests roadmap item.
#include "setti_loot_inc"
#include "my_createbelt"

void main()
{
    object oPC     = GetLastOpenedBy();
    object oChest  = OBJECT_SELF;

    if(!GetIsPC(oPC)) return;
    if(!SettiReady(oChest)) return;   // still cooling down -> opens empty

    CreateBelt(oChest, oPC, 60);
    SettiMarkDrawn(oChest);
}
