//::///////////////////////////////////////////////
//:: Dye Kit - Dye Item
//:: dye_dyeitem.nss
//:: Copyright (c) 2003 Jake E. Fitch
//:://////////////////////////////////////////////
/*
    Dye the item.
*/
//:://////////////////////////////////////////////
//:: Created By: Jake E. Fitch (Milambus Mandragon)
//:: Created On: Jan. 10, 2004
//:://////////////////////////////////////////////
void main()
{
    object oPC = OBJECT_SELF;
    object oChest = GetObjectByTag("ClothingBuilder");

    int iItemToDye = GetLocalInt(oPC, "ItemToDye");
    int iMaterialToDye = GetLocalInt(oPC, "MaterialToDye");
    int iColorGroup = GetLocalInt(oPC, "ColorGroup");
    int iColorToDye = GetLocalInt(oPC, "ColorToDye");

    int iColor = (iColorGroup * 8) + iColorToDye;
    object oItem = GetItemInSlot(iItemToDye, oPC);

    if (GetIsObjectValid(oItem)) {
        // Set armor to being edited
        SetLocalInt(oItem, "mil_EditingItem", TRUE);

        // Preserve the forge legality stamps across the dye (CopyItemAndModify can
        // drop item-local ints; losing FORGE_CEIL makes the contraband scan jail
        // a lawfully-forged >750k item). Capture before oItem is destroyed.
        int nCeil  = GetLocalInt(oItem, "FORGE_CEIL");
        int nClean = GetLocalInt(oItem, "FORGE_CLEAN");

        // Copy item to the chest
        object oInChest = CopyItem(oItem, oChest, TRUE);
        DestroyObject(oItem);

        // Dye the item
        object oDyedItem = CopyItemAndModify(oInChest, ITEM_APPR_TYPE_ARMOR_COLOR, iMaterialToDye, iColor, TRUE);
        DestroyObject(oInChest);

        // Copy the armor back to the PC
        object oOnPC = CopyItem(oDyedItem, oPC, TRUE);
        DestroyObject(oDyedItem);

        // Re-apply the forge legality stamps captured above.
        if (nCeil)  SetLocalInt(oOnPC, "FORGE_CEIL", nCeil);
        if (nClean) SetLocalInt(oOnPC, "FORGE_CLEAN", nClean);

        // Equip the armor
       DelayCommand(0.5f, AssignCommand(oPC, ActionEquipItem(oOnPC, iItemToDye)));

       // Set armor editable again
       DelayCommand(3.0f, DeleteLocalInt(oOnPC, "mil_EditingItem"));
    }
}
