// meth_chest_dist - OnInvDisturbed of the invisible storage locker
// (meth_chest_inv). Refuses containers (no nested-storage exploit) and
// re-snapshots the locker to the campaign DB under the owner's CD key shortly
// after any add/remove, so stored items persist across the account's characters
// and server restarts.
#include "meth_house_inc"

void main()
{
    object oPC = GetLastDisturbed();
    if (!GetIsPC(oPC)) return;

    object oLocker = OBJECT_SELF;
    string sKey = GetLocalString(oLocker, "meth_cdkey");
    if (sKey == "") sKey = GetPCPublicCDKey(oPC);

    int iType = GetInventoryDisturbType();
    object oItem = GetInventoryDisturbItem();

    // No containers - they could nest unlimited items and dodge any future cap.
    if (iType == INVENTORY_DISTURB_TYPE_ADDED && GetHasInventory(oItem))
    {
        DelayCommand(0.3, AssignCommand(oLocker, ActionGiveItem(oItem, oPC)));
        SendMessageToPC(oPC, "You cannot store containers here.");
        return;
    }

    // Debounced full-snapshot save.
    DelayCommand(1.0, MethChestSave(oLocker, sKey));
}
