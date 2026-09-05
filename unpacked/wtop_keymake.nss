// The ward-forge below Amon Sul (roadmap: forbidden-realms-key-tier)
//
// OnUsed for the area028 placeable tagged wtop_key_maker ("Floor lever"),
// standing beside wtop_key_box ("Mysterious Object", an old oven). The admin's
// recipe:
//
//   kill the four Amon Sul unit types for their four key-shards (a per-player,
//   per-type 33/66/100% pity cycle - at most three kills of a type per shard,
//   see wtop_death.nss) -> put one of EACH into the oven -> pull this lever ->
//   look in the oven again and the whole key is inside -> that key opens
//   wtop_4key_door once and is eaten in the turning.
//
// The four shards are consumed. Spares are NOT: a party that dropped in eight
// shards keeps the other four, so two characters can each make a key from one
// oven without either of them losing a ward to the other's pull.
//
// The oven is Plot in the toolset, so nothing here can destroy the container
// itself; only its contents are touched.

const string WTOP_BOX_TAG  = "wtop_key_box";
const string WTOP_KEY_RR   = "wtop_4key_whole";

const string SHARD_1 = "wtop_4key_arrow";
const string SHARD_2 = "wtop_4key_blade";
const string SHARD_3 = "wtop_4key_shade";
const string SHARD_4 = "wtop_4key_grave";

// First item in oBox carrying sTag, or OBJECT_INVALID. Shards are tag == resref
// by construction (see bin-built wtop_4key_*.uti.json), so either lookup works;
// the tag form is the one that survives someone re-minting a shard blueprint.
object WtopShardIn(object oBox, string sTag)
{
    object oItem = GetFirstItemInInventory(oBox);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == sTag) return oItem;
        oItem = GetNextItemInInventory(oBox);
    }
    return OBJECT_INVALID;
}

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    object oBox = GetNearestObjectByTag(WTOP_BOX_TAG, OBJECT_SELF);
    if (!GetIsObjectValid(oBox))
    {
        SendMessageToPC(oPC, "The lever grinds, and nothing answers it.");
        return;
    }

    object o1 = WtopShardIn(oBox, SHARD_1);
    object o2 = WtopShardIn(oBox, SHARD_2);
    object o3 = WtopShardIn(oBox, SHARD_3);
    object o4 = WtopShardIn(oBox, SHARD_4);

    if (!GetIsObjectValid(o1) || !GetIsObjectValid(o2)
        || !GetIsObjectValid(o3) || !GetIsObjectValid(o4))
    {
        // Name what is missing rather than just failing: four different unit
        // types drop these and a player has no other way to learn which one
        // they are still short of.
        string sMissing = "";
        if (!GetIsObjectValid(o1)) sMissing += "\n  the Arrow Ward (Weathertop Archers)";
        if (!GetIsObjectValid(o2)) sMissing += "\n  the Blade Ward (Weathertop Fighters)";
        if (!GetIsObjectValid(o3)) sMissing += "\n  the Shadow Ward (Weathertop Scouts)";
        if (!GetIsObjectValid(o4)) sMissing += "\n  the Grave Ward (the barrow-wights)";

        AssignCommand(OBJECT_SELF, PlaySound("as_dr_locked1"));
        SendMessageToPC(oPC, "The oven shudders, cools, and gives nothing back. "
            + "The wards inside are not a whole ward. Still wanting:" + sMissing);
        return;
    }

    DestroyObject(o1); DestroyObject(o2);
    DestroyObject(o3); DestroyObject(o4);

    CreateItemOnObject(WTOP_KEY_RR, oBox);

    ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                          EffectVisualEffect(VFX_FNF_SCREEN_SHAKE),
                          GetLocation(oBox));
    AssignCommand(oBox, PlaySound("as_dr_metllgcl1"));

    SendMessageToPC(oPC, "The lever drops. Something inside the oven takes a "
        + "long breath of heat, and the four wards run together into one. "
        + "Whatever is in there now, it is not four pieces any more.");
}
