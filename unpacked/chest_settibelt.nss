// chest_settibelt.nss -- OnOpen of the Setti belt coffer (Numenor: Noirinan).
// Rolls one Legendary belt (Loot Overhaul profile "setti_belt": rarity floor Legendary,
// at Noirinan's loot level), at most once per cooldown per chest. Replaced the
// fixed my_createbelt pool on 2026-11-05 (admin). The profile and its
// "custom" entry live in loot/sources.json; see setti_loot_inc.nss and the
// numenor-chests roadmap item for the cooldown and re-lock.
#include "setti_loot_inc"
#include "loot_inc"

void main()
{
    object oPC     = GetLastOpenedBy();
    object oChest  = OBJECT_SELF;

    if(!GetIsPC(oPC)) return;
    if(!SettiReady(oChest)) return;   // still cooling down -> opens empty

    Loot_FillContainer(oChest, "setti_belt", Loot_ContainerLevel(oChest), oPC);
    SettiMarkDrawn(oChest);
}
