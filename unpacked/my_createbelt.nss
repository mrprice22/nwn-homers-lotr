// my_createbelt.nss -- loot for the Setti belt-coffer in Numenor: Noirinan.
//
// A near-end-game chest: mints one random end-game belt for the opener. The old
// pool (be_all_* / be_wizard_* ...) referenced blueprints that do not exist in
// the module, so the chest minted nothing; it was also level-gated to HD<=12,
// excluding the level-40 characters who actually reach Noirinan. Both are fixed:
// the pool is a curated set of real end-game belts and the cap is raised at the
// call site (chest_settibelt passes 60). See the numenor-chests roadmap item.
//
// Selection is vetted against module-index/inaccessible_items.json: every entry
// is a complete, non-plot belt -- either already dropped by a boss (a second
// source is harmless) or a source-less "orphan" this chest gives a home to.

#include "my_charfuncs"

void CreateBelt(object oContainer, object oPC, int nMaxLevel)
{
    string sItem;

    if(!GetIsPC(oPC) || (GetHitDice(oPC) > nMaxLevel))
        return;

    switch(Random(6) + 1)
    {
        case 1: sItem = "beltofgreatness";  break; // Belt of Greatness (Balrog)
        case 2: sItem = "beltofsorcerery";  break; // Belt of Sorcerery (Gandalf)
        case 3: sItem = "beltofdarkwardin"; break; // Belt of Dark Warding (Khamul)
        case 4: sItem = "item121";          break; // Sauron's Chosen Belt
        case 5: sItem = "epicbelt";         break; // Epic Belt (orphan)
        case 6: sItem = "beltofpower002";   break; // Belt of Power (orphan)
    }

    if(sItem != "")
        CreateItemOnObject(sItem, oContainer, 1);
}
