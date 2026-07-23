// chest_settishld.nss -- OnOpen of SettiShieldChest (Numenor: Noirinan).
// Mint one end-game shield, at most once per cooldown per chest (see
// setti_loot_inc.nss and the numenor-chests roadmap item).
#include "setti_loot_inc"
#include "my_createshield"

void main()
{
    object oPC    = GetLastOpenedBy();
    object oChest = OBJECT_SELF;

    if(!GetIsPC(oPC)) return;
    if(!SettiReady(oChest)) return;   // still cooling down -> opens empty

    CreateShield(oChest, oPC, 60);
    SettiMarkDrawn(oChest);
}
