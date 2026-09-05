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
// DROP RULE (2026-09-04, replaces the flat 42% roll)
//
// The flat roll tested at 15-20%, not the 42% it was written for, and a flat
// roll has no floor anyway: a run of bad luck on one unit type can stall the
// whole set indefinitely. This is now a per-player, per-type pity counter -
// the shard drops within at most three kills of that type, and the counter
// resets the moment it pays out:
//
//   1st kill since the last shard   33%
//   2nd kill since the last shard   66%
//   3rd kill since the last shard  100%  (guaranteed)
//
// Average is ~1.9 kills per shard, i.e. an effective ~53% per kill, and a
// player who wants to farm keys can: nothing here caps how many times the
// cycle runs.
//
// The counter is per PC and per unit type, held in the "wtopkeys" campaign DB
// so it survives a relog - a player two kills into an archer cycle does not
// lose that by logging out. Four counters per character, one int each.
//
// Kill credit: the old script required GetLastKiller() to be a PC outright,
// so every kill landed by a summon, familiar, animal companion or henchman
// paid nothing. That is the likeliest reason the observed rate ran so far
// under the intended one - most of this garrison dies to associates. The
// killer's master is now resolved first, so an associate's kill credits its
// owner.
//
// The shard is created on the corpse BEFORE the default death handler runs, so
// it lands in the death loot the party actually opens. x2_def_ondeath then
// chains nw_c2_default7 -> SE_DoCreatureRespawn as usual: this wrapper adds
// loot and changes nothing about respawn. tests/check_creature_respawn.py
// follows the ExecuteScript below, so the gate still sees the respawn path.

const string WTOP_KEY_DB = "wtopkeys";

// Kills of one type since that type last paid out, 1-based (this kill counted).
const int WTOP_PITY_KILLS = 3;

string WtopShardFor(string sResRef)
{
    if (sResRef == "weathertoparc001") return "wtop_4key_arrow";
    if (sResRef == "weathertopfighte") return "wtop_4key_blade";
    if (sResRef == "wtop_scout")       return "wtop_4key_shade";
    if (sResRef == "wtop_zombie")      return "wtop_4key_grave";
    return "";
}

// 33 / 66 / 100 on the first, second and third kill of a cycle. Anything past
// the third would already have paid out, but clamp rather than trust that.
int WtopChanceFor(int nKill)
{
    if (nKill <= 1) return 33;
    if (nKill == 2) return 66;
    return 100;
}

void main()
{
    string sShard = WtopShardFor(GetResRef(OBJECT_SELF));
    if (sShard == "")
    {
        ExecuteScript("x2_def_ondeath", OBJECT_SELF);
        return;
    }

    // Credit the owner when an associate landed the blow; a guard cut down by
    // a hostile NPC (or by the leash) still pays nothing.
    object oPC = GetLastKiller();
    if (!GetIsPC(oPC))
    {
        object oMaster = GetMaster(oPC);
        if (GetIsPC(oMaster)) oPC = oMaster;
    }

    if (GetIsPC(oPC))
    {
        // One counter per shard type, so farming archers cannot advance the
        // barrow-wight cycle.
        int nKill = GetCampaignInt(WTOP_KEY_DB, sShard, oPC) + 1;

        if (d100() <= WtopChanceFor(nKill) || nKill >= WTOP_PITY_KILLS)
        {
            CreateItemOnObject(sShard, OBJECT_SELF);
            nKill = 0;                    // cycle paid out, start over
        }

        SetCampaignInt(WTOP_KEY_DB, sShard, nKill, oPC);
    }

    ExecuteScript("x2_def_ondeath", OBJECT_SELF);
}
