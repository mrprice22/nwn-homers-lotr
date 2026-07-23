// my_createring.nss -- loot for the Setti ring-coffer in Numenor: Noirinan.
//
// A near-end-game chest: mints one random end-game ring for the opener. The old
// pool referenced ri_all_* blueprints that do not exist and was level-gated to
// HD<=12, so it was dead for the level-40 characters who reach Noirinan. Fixed:
// a curated end-game ring pool, cap raised at the call site (ches_settiring
// passes 60). See the numenor-chests roadmap item.
//
// Selection vetted against module-index/inaccessible_items.json -- complete,
// non-plot rings only; iconic/lore-locked uniques (The One Ring, Arwen's ring)
// and god/joke items are deliberately excluded.

#include "my_charfuncs"

void CreateRing(object oContainer, object oPC, int nMaxLevel)
{
    string sItem;

    if(!GetIsPC(oPC) || (GetHitDice(oPC) > nMaxLevel))
        return;

    switch(Random(6) + 1)
    {
        case 1: sItem = "101";             break; // Lightstream Ring (Gwathdor Lord)
        case 2: sItem = "it_mring030";     break; // Ring of Fortitude +20
        case 3: sItem = "keeperring";      break; // The Keeper's Ring
        case 4: sItem = "ringoftheshad001"; break; // Ring of the Shadow Lord
        case 5: sItem = "054";             break; // Chosen's Ring of the Dark
        case 6: sItem = "it_mring042";     break; // Ring of Regeneration +10 (orphan)
    }

    if(sItem != "")
        CreateItemOnObject(sItem, oContainer, 1);
}
