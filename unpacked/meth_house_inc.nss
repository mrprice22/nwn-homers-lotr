// meth_house_inc - shared helpers for the Methonash's Place player house
// (and any future player house built on the same plumbing).
//
// Ownership is decided entirely by the key-free admindb `houses` table
// (see admin_db.nss). No CD keys appear in source - the chest/key-ring just
// ask Admin_OwnsAreaHouse(). Persistence uses the legacy Bioware campaign
// object store (same mechanism as the module's PPIS chests), keyed by the
// owner's CD key, so a house's stored items follow the CD key across all of
// that account's characters.

const string MCH_DB        = "housechest";       // campaign object DB (items)
const string MCH_LOCKER_RR = "meth_chest_inv";   // invisible storage placeable
const string MCH_STORE_CRE = "ppis_individual";  // invisible item-carrier creature

// 50 magical damage + the standard refusal message, for anyone who tries to
// use a house fixture they don't own.
void MethZapUnauthorized(object oPC)
{
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
                        EffectDamage(50, DAMAGE_TYPE_MAGICAL), oPC);
    FloatingTextStringOnCreature("You are not authorized to use this", oPC, FALSE);
}

// Snapshot oLocker's contents into the campaign DB under sKey (creature method:
// copy items onto an invisible carrier creature, store the creature, destroy it).
void MethChestSave(object oLocker, string sKey)
{
    if (sKey == "") return;
    location lLoc = GetLocation(oLocker);
    object oCre = CreateObject(OBJECT_TYPE_CREATURE, MCH_STORE_CRE, lLoc, FALSE, sKey);
    if (!GetIsObjectValid(oCre)) return;
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
                        EffectVisualEffect(VFX_DUR_CUTSCENE_INVISIBILITY), oCre);
    object oItem = GetFirstItemInInventory(oLocker);
    while (GetIsObjectValid(oItem))
    {
        CopyItem(oItem, oCre, TRUE);
        oItem = GetNextItemInInventory(oLocker);
    }
    StoreCampaignObject(MCH_DB, sKey, oCre);
    DestroyObject(oCre, 0.2);
}

// Get (creating + DB-loading on first use this session) the invisible locker
// that backs visible chest oChest for owner CD key sKey. The locker is spawned
// 10m underground so players can never click it directly.
object MethChestGetLocker(object oChest, string sKey)
{
    object oLocker = GetLocalObject(oChest, "meth_locker");
    if (GetIsObjectValid(oLocker)) return oLocker;

    vector v = GetPosition(oChest);
    location lLoc = Location(GetArea(oChest), Vector(v.x, v.y, v.z - 10.0),
                             GetFacing(oChest));
    oLocker = CreateObject(OBJECT_TYPE_PLACEABLE, MCH_LOCKER_RR, lLoc, FALSE);
    SetLocalString(oLocker, "meth_cdkey", sKey);
    SetLocalObject(oChest, "meth_locker", oLocker);

    object oCre = RetrieveCampaignObject(MCH_DB, sKey, lLoc);
    if (GetIsObjectValid(oCre))
    {
        object oItem = GetFirstItemInInventory(oCre);
        while (GetIsObjectValid(oItem))
        {
            CopyItem(oItem, oLocker, TRUE);
            oItem = GetNextItemInInventory(oCre);
        }
        DestroyObject(oCre, 0.2);
    }
    return oLocker;
}
