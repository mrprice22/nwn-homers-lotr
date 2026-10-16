// hw26_hearth - Harvest Hearth: place it inside your own player house, where
// it stays for good (restored every boot from halloweendb). Single use.

#include "hw_inc"
#include "admin_db"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    object oItem = GetLocalObject(oPC, "hw_item");
    object oArea = GetArea(oPC);
    if (!Admin_OwnsAreaHouse(oPC, GetTag(oArea)))
    {
        SendMessageToPC(oPC, "The Harvest Hearth can only be set down inside your own house.");
        return;
    }
    location l = GetLocation(oPC);
    vector v = GetPositionFromLocation(l);
    int nYear = HW_Year();
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "INSERT INTO hw_hearth (hkey, area_tag, x, y, z, f, cdkey, pc_name, year) " +
        "VALUES (@k, @a, @x, @y, @z, @f, @c, @n, @yr)");
    SqlBindString(q, "@k", IntToString(HW_Now()) + "_" + IntToString(Random(1000000)));
    SqlBindString(q, "@a", GetTag(oArea));
    SqlBindFloat(q, "@x", v.x);
    SqlBindFloat(q, "@y", v.y);
    SqlBindFloat(q, "@z", v.z);
    SqlBindFloat(q, "@f", GetFacing(oPC));
    SqlBindString(q, "@c", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlBindInt(q, "@yr", nYear);
    SqlStep(q);
    object o = HW_PlaceHearth(l);
    SetName(o, GetName(oPC) + "'s Harvest Hearth (" + IntToString(nYear) + ")");
    DestroyObject(oItem);
    SendMessageToPC(oPC, "The Harvest Hearth settles in. It will be here every time you come home.");
}
