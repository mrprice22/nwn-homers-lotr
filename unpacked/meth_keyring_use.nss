// meth_keyring_use — OnUsed of the MethonashsKeyring placeable. Each use hands
// the house owner a fresh copy of their door key (no cap); anyone else is zapped
// for 50 and refused. The key resref comes from the admindb houses row, so the
// same placeable script is reusable for any future house — no CD keys in source.
#include "admin_db"
#include "meth_house_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    // Keyed by the house's AREA tag — reusable for any future house unchanged.
    string sAreaTag = GetTag(GetArea(OBJECT_SELF));
    if (!Admin_OwnsAreaHouse(oPC, sAreaTag))
    {
        MethZapUnauthorized(oPC);
        return;
    }

    string sRR = Admin_GetHouseKeyResref(sAreaTag);
    if (sRR == "") return;

    CreateItemOnObject(sRR, oPC, 1);
    FloatingTextStringOnCreature("A key materialises in your pack.", oPC, FALSE);
}
