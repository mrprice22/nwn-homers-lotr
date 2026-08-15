// Forge gate for the melee-only enchantments: On Hit Properties, Keen and
// Vampiric Regeneration. BASE_ITEM_SLING is deliberately NOT in this list --
// it is a ranged weapon and belongs to israngedweapon.nss.
int StartingConditional()
{
    object oItem = GetLocalObject(GetPCSpeaker(), "MODIFY_ITEM");
    int iTyp = GetBaseItemType(oItem);
    return (
        (iTyp == BASE_ITEM_BASTARDSWORD ) ||
        (iTyp == BASE_ITEM_BATTLEAXE ) ||
        (iTyp == BASE_ITEM_CLUB ) ||
        (iTyp == BASE_ITEM_DAGGER ) ||
        (iTyp == BASE_ITEM_DIREMACE ) ||
        (iTyp == BASE_ITEM_DOUBLEAXE ) ||
        (iTyp == BASE_ITEM_DWARVENWARAXE ) ||
        (iTyp == BASE_ITEM_GREATAXE ) ||
        (iTyp == BASE_ITEM_GREATSWORD ) ||
        (iTyp == BASE_ITEM_HALBERD ) ||
        (iTyp == BASE_ITEM_HANDAXE ) ||
        (iTyp == BASE_ITEM_HEAVYFLAIL ) ||
        (iTyp == BASE_ITEM_KAMA ) ||
        (iTyp == BASE_ITEM_KATANA ) ||
        (iTyp == BASE_ITEM_KUKRI ) ||
        (iTyp == BASE_ITEM_LIGHTFLAIL ) ||
        (iTyp == BASE_ITEM_LIGHTHAMMER ) ||
        (iTyp == BASE_ITEM_LIGHTMACE ) ||
        (iTyp == BASE_ITEM_LONGSWORD ) ||
        (iTyp == BASE_ITEM_MAGICSTAFF ) ||
        (iTyp == BASE_ITEM_MORNINGSTAR ) ||
        (iTyp == BASE_ITEM_QUARTERSTAFF ) ||
        (iTyp == BASE_ITEM_RAPIER ) ||
        (iTyp == BASE_ITEM_SCIMITAR ) ||
        (iTyp == BASE_ITEM_SCYTHE ) ||
        (iTyp == BASE_ITEM_SHORTSPEAR ) ||
        (iTyp == BASE_ITEM_SHORTSWORD ) ||
        (iTyp == BASE_ITEM_SICKLE ) ||
        (iTyp == BASE_ITEM_WARHAMMER ) ||
        (iTyp == BASE_ITEM_WHIP )
        );
}


