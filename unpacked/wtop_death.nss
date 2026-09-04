// Weather Top / Amon Sul garrison OnDeath (roadmap: forbidden-realms-key-tier)
//
// The hill garrison guards the way into the hidden court, and the way in is a
// key struck into four wards. Each of the four unit types on Amon Sul carries
// exactly one of them:
//
//   weathertoparc001  Weathertop Archer          -> wtop_4key_arrow
//   weathertopfighte  Weathertop Fighter         -> wtop_4key_blade
//   wtop_scout        Weathertop Scout           -> wtop_4key_shade
//   wtop_zombie       Barrow-wight of Amon Sul   -> wtop_4key_grave
//
// 42% per kill, per the admin's spec: a player has to work through several of
// each type before all four wards are in hand, and cannot farm one easy unit
// type for the whole set.
//
// The shard is created on the corpse BEFORE the default death handler runs, so
// it lands in the death loot the party actually opens. x2_def_ondeath then
// chains nw_c2_default7 -> SE_DoCreatureRespawn as usual: this wrapper adds
// loot and changes nothing about respawn. tests/check_creature_respawn.py
// follows the ExecuteScript below, so the gate still sees the respawn path.

const int WTOP_SHARD_PCT = 42;

string WtopShardFor(string sResRef)
{
    if (sResRef == "weathertoparc001") return "wtop_4key_arrow";
    if (sResRef == "weathertopfighte") return "wtop_4key_blade";
    if (sResRef == "wtop_scout")       return "wtop_4key_shade";
    if (sResRef == "wtop_zombie")      return "wtop_4key_grave";
    return "";
}

void main()
{
    string sShard = WtopShardFor(GetResRef(OBJECT_SELF));

    // Only a kill a player was actually part of pays out; a guard cut down by
    // another NPC (or by the leash) is not a loot source.
    if (sShard != "" && GetIsPC(GetLastKiller()) && d100() <= WTOP_SHARD_PCT)
        CreateItemOnObject(sShard, OBJECT_SELF);

    ExecuteScript("x2_def_ondeath", OBJECT_SELF);
}
