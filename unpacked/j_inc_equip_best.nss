/************************ [Include - Best Melee Weapon] ************************
    Filename: J_INC_EQUIP_BEST
************************* [Include - Best Melee Weapon] ************************
    Custom replacement for ActionEquipMostDamagingMelee().

    The engine builtin scores weapons by gold piece value, which breaks for
    high-value module weapons. This implementation scores by actual damage
    output: base die size + enhancement bonus + damage bonus properties.

    No includes required - uses only engine builtins.
************************* [Include - Best Melee Weapon] ***********************/

// Returns a numeric damage score for a melee weapon based on actual combat
// output, not gold piece value. Returns 0 for non-weapons or unknown types.
int GetMeleeWeaponDamageScore(object oItem);

// Equips the highest-scoring melee weapon found in inventory.
// Drop-in replacement for ActionEquipMostDamagingMelee().
void EquipBestMeleeWeapon(object oTarget = OBJECT_INVALID);

//------------------------------------------------------------------------------

int GetMeleeWeaponDamageScore(object oItem)
{
    int nScore;
    int nType;
    itemproperty ip;

    // Base score = max value of the weapon's damage die.
    // Returns 0 for unknown or non-weapon types (they will be skipped).
    switch (GetBaseItemType(oItem))
    {
        // d4 weapons
        case BASE_ITEM_DAGGER:         nScore = 4;  break;
        case BASE_ITEM_KUKRI:          nScore = 4;  break;
        case BASE_ITEM_LIGHTHAMMER:    nScore = 4;  break;
        case BASE_ITEM_WHIP:           nScore = 4;  break;
        // d6 weapons
        case BASE_ITEM_CLUB:           nScore = 6;  break;
        case BASE_ITEM_HANDAXE:        nScore = 6;  break;
        case BASE_ITEM_KAMA:           nScore = 6;  break;
        case BASE_ITEM_LIGHTMACE:      nScore = 6;  break;
        case BASE_ITEM_QUARTERSTAFF:   nScore = 6;  break;
        case BASE_ITEM_RAPIER:         nScore = 6;  break;
        case BASE_ITEM_SCIMITAR:       nScore = 6;  break;
        case BASE_ITEM_SHORTSPEAR:     nScore = 6;  break;
        case BASE_ITEM_SHORTSWORD:     nScore = 6;  break;
        case BASE_ITEM_SICKLE:         nScore = 6;  break;
        case BASE_ITEM_MAGICSTAFF:     nScore = 6;  break;
        // d8 weapons
        case BASE_ITEM_BASTARDSWORD:   nScore = 8;  break;
        case BASE_ITEM_BATTLEAXE:      nScore = 8;  break;
        case BASE_ITEM_DIREMACE:       nScore = 8;  break;
        case BASE_ITEM_DOUBLEAXE:      nScore = 8;  break;
        case BASE_ITEM_DWARVENWARAXE:  nScore = 8;  break;
        case BASE_ITEM_KATANA:         nScore = 8;  break;
        case BASE_ITEM_LIGHTFLAIL:     nScore = 8;  break;
        case BASE_ITEM_LONGSWORD:      nScore = 8;  break;
        case BASE_ITEM_MORNINGSTAR:    nScore = 8;  break;
        case BASE_ITEM_SCYTHE:         nScore = 8;  break;
        case BASE_ITEM_WARHAMMER:      nScore = 8;  break;
        // d10 weapons
        case BASE_ITEM_HEAVYFLAIL:     nScore = 10; break;
        case BASE_ITEM_HALBERD:        nScore = 10; break;
        // d12 / 2d6 weapons
        case BASE_ITEM_GREATAXE:       nScore = 12; break;
        case BASE_ITEM_GREATSWORD:     nScore = 12; break;
        default:                       nScore = 0;  break;
    }

    if (nScore == 0)
        return 0;

    // Add bonuses from item properties
    ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        nType = GetItemPropertyType(ip);
        if (nType == ITEM_PROPERTY_ENHANCEMENT_BONUS)
        {
            // Weight enhancement bonus double: it improves both attack and damage
            nScore += GetItemPropertyCostTableValue(ip) * 2;
        }
        else if (nType == ITEM_PROPERTY_DAMAGE_BONUS)
        {
            nScore += GetItemPropertyCostTableValue(ip);
        }
        else if (nType == ITEM_PROPERTY_DAMAGE_BONUS_VS_ALIGNMENT_GROUP ||
                 nType == ITEM_PROPERTY_DAMAGE_BONUS_VS_RACIAL_GROUP ||
                 nType == ITEM_PROPERTY_DAMAGE_BONUS_VS_SPECIFIC_ALIGNMENT)
        {
            nScore += 1;
        }
        ip = GetNextItemProperty(oItem);
    }
    return nScore;
}

void EquipBestMeleeWeapon(object oTarget = OBJECT_INVALID)
{
    object oBest = OBJECT_INVALID;
    int nBestScore = 0;
    int nScore;

    object oItem = GetFirstItemInInventory();
    while (GetIsObjectValid(oItem))
    {
        if (GetWeaponRanged(oItem) == FALSE)
        {
            nScore = GetMeleeWeaponDamageScore(oItem);
            if (nScore > nBestScore)
            {
                nBestScore = nScore;
                oBest = oItem;
            }
        }
        oItem = GetNextItemInInventory();
    }

    if (GetIsObjectValid(oBest))
    {
        ActionEquipItem(oBest, INVENTORY_SLOT_RIGHTHAND);
    }
}
