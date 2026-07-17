// q_dwd_stone -- the Dwarven Defenders' standing-stone (roadmap:
// dwarven-defender-quest). OnUsed of the headstone of Balin, son of
// Fundin, in Balin's Tomb (balinstomb.git.json, existing placed instance
// 86 reused -- retagged DwdBalinStone; it was already usable + plot with
// no scripts, so there is nothing to chain, and no script referenced the
// generic old tag "Headstone". The shadowdancer quest's hook in the same
// area is the DeepWell, instance 52 -- untouched). Runs the war-weight
// stand for a PC on the trial:
//
//   * The war-weight fail condition: come to the tomb in leathers,
//     robes, light mail or a bare chest (QDWD_IsStoneClad -- the chest
//     armor's BASE AC from parts_chest.2da must be 6+, i.e. splint /
//     banded / half-plate / full plate; enhancement bonuses cannot fake
//     it), and the attempt fails with a flavor message; nothing is
//     granted. Retry allowed -- put on heavy iron and stand again.
//     Deterministic: the weight is the test, no dice.
//   * Heavy iron at stage 1: gives the shard, stage 1 -> 2 + journal 2.
//     At stage 2 with the shard lost, re-gives it (never duplicates --
//     GetItemPossessedBy guard; the item is plot + cursed and only the
//     finish consumes it).
//
// Does nothing for PCs not on the trial -- to everyone else it is just
// Balin's carefully chiseled headstone.
#include "q_dwd_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QDWD_GetStage(oPC);
    if (nStage < QDWD_STAGE_ACCEPTED || nStage > QDWD_STAGE_SHARD) return;
    if (QDWD_HasShard(oPC)) return;

    // The fail condition: no war-weight on the shoulders. The stone does
    // not know a defender in traveler's leathers.
    if (!QDWD_IsStoneClad(oPC))
    {
        FloatingTextStringOnCreature(
            "You set your hand on Balin's stone, and the stone does not "
            + "know you. His guard stood here in the war-weight of Khazad "
            + "-- splint and plate, iron enough to be a wall. Come clad as "
            + "they came, and stand again.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QDWD_SHARD_RES, oPC, 1);

    if (nStage == QDWD_STAGE_ACCEPTED)
    {
        QDWD_SetStage(oPC, QDWD_STAGE_SHARD);
        AddJournalQuestEntry(QDWD_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "The stand is kept: iron on your shoulders, your feet planted "
        + "where his guard planted theirs. Under your palm the unbroken "
        + "stone parts with a single shard, clean-edged and heavier than "
        + "it should be, and the tomb is quiet again. Carry it to Halmir.",
        oPC, FALSE);
}
