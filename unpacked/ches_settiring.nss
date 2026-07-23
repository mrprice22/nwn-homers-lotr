// ches_settiring.nss -- OnOpen of SettiRingChest (Numenor: Noirinan).
// Mint one end-game ring, at most once per cooldown per chest (see
// setti_loot_inc.nss and the numenor-chests roadmap item).
#include "setti_loot_inc"
#include "my_createring"

void main()
{
    object oPC    = GetLastOpenedBy();
    object oChest = OBJECT_SELF;

    if(!GetIsPC(oPC)) return;
    if(!SettiReady(oChest)) return;   // still cooling down -> opens empty

    CreateRing(oChest, oPC, 60);
    SettiMarkDrawn(oChest);
}
