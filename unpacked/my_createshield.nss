// my_createshield.nss -- loot for the Setti shield-coffer in Numenor: Noirinan.
//
// A near-end-game chest: mints one random end-game shield for the opener. The
// old pool referenced sh_all_* blueprints that do not exist and was level-gated
// to HD<=12 (the HD 0-5 band was even Random(0)), so it was dead for the
// level-40 characters who reach Noirinan. Fixed: a curated end-game shield pool,
// cap raised at the call site (chest_settishld passes 60). See the
// numenor-chests roadmap item.
//
// Selection vetted against module-index/inaccessible_items.json -- complete,
// non-plot shields only; a mix of boss-dropped and source-less "orphan" shields
// this chest gives a home to.

#include "my_charfuncs"

void CreateShield(object oContainer, object oPC, int nMaxLevel)
{
    string sItem;

    if(!GetIsPC(oPC) || (GetHitDice(oPC) > nMaxLevel))
        return;

    switch(Random(6) + 1)
    {
        case 1: sItem = "shieldmaiden";     break; // Shieldmaiden (Eowyn)
        case 2: sItem = "148";              break; // Greater Shield of the Deep
        case 3: sItem = "shieldofthero002"; break; // Shield of Elrond
        case 4: sItem = "shieldofboromir";  break; // Shield of Boromir
        case 5: sItem = "epicshield";       break; // Epic Shield (orphan)
        case 6: sItem = "shieldofithilien"; break; // Elite Shield of Ithilien (orphan)
    }

    if(sItem != "")
        CreateItemOnObject(sItem, oContainer, 1);
}
