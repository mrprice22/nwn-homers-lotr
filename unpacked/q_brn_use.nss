// q_brn_use — Beorn's Garden hive OnUsed (roadmap: beorns-garden)
// Harvest a honey hive: once per PC per hive per day (questcddb calendar
// key beorn_garden_h<idx> — relog/restart-safe). Every harvest angers the
// hive's raiders and spawns a warg pack at the hive's own location. If the
// honey leg is done but pelts still run short, re-using a harvested hive
// rattles it and calls another pack, so the day can always be finished
// (spawns stay capped per-area in BRN_SpawnWargs).
#include "q_brn_inc"

void main()
{
    object oHive = OBJECT_SELF;
    object oPC   = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    if (!BRN_IsActive(oPC))
    {
        FloatingTextStringOnCreature(
            "The hive hums with bees. Grimbeorn the Old would not thank you "
            + "for meddling uninvited.", oPC, FALSE);
        return;
    }

    int nIdx = GetLocalInt(oHive, "q_brn_idx");
    string sKey = BRN_HIVE_KEY + IntToString(nIdx);

    if (!QCD_IsDoneToday(oPC, sKey))
    {
        QCD_Stamp(oPC, sKey);
        FloatingTextStringOnCreature("You cut a dripping comb from the hive ("
            + IntToString(BRN_CountHoney(oPC)) + " of "
            + IntToString(BRN_NEED_HONEY) + ").", oPC, FALSE);
        if (BRN_SpawnWargs(oHive) > 0)
            FloatingTextStringOnCreature(
                "Wargs burst from the brush, drawn by the broken hive!",
                oPC, FALSE);
        return;
    }

    // Already harvested this hive today.
    if (BRN_CountHoney(oPC) >= BRN_NEED_HONEY
        && BRN_CountPelts(oPC) < BRN_NEED_PELTS)
    {
        if (BRN_SpawnWargs(oHive) > 0)
            FloatingTextStringOnCreature(
                "You rattle the emptied hive -- and the wargs come running.",
                oPC, FALSE);
        else
            FloatingTextStringOnCreature(
                "The wargs already prowling nearby must fall first.",
                oPC, FALSE);
        return;
    }

    FloatingTextStringOnCreature(
        "You have already drawn this hive's honey today.", oPC, FALSE);
}
