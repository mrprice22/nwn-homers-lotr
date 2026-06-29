// meth_chest_open — OnUsed of the visible "Persistent Chest" (tag cAwesomec)
// in Methonash's Place. The visible chest carries NO inventory of its own
// (HasInventory=0) so clicking it can never auto-open anything; access is gated
// here and routed to an invisible per-owner locker backed by the campaign DB.
#include "admin_db"
#include "meth_house_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    // Ownership is keyed by the house's AREA tag, so this script is reusable for
    // any future house without edits.
    if (!Admin_OwnsAreaHouse(oPC, GetTag(GetArea(OBJECT_SELF))))
    {
        MethZapUnauthorized(oPC);
        return;
    }

    object oLocker = MethChestGetLocker(OBJECT_SELF, GetPCPublicCDKey(oPC));
    AssignCommand(oPC, ActionInteractObject(oLocker));
}
