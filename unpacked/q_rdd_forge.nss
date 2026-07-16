// q_rdd_forge -- The Forge of Durin (roadmap: red-dragon-disciple-quest).
// OnUsed of the old forge-anvil in the Lonely Mountain's main hall
// (lonelymountainma.git.json, existing placed instance reused -- retagged
// DurinForge; it was already usable and had no previous OnUsed, so there
// is nothing to chain). Runs the Red Dragon Disciples' trial for a PC on
// the rite:
//
//   * The blood-must-feel-the-flame fail condition: if the PC stands
//     wrapped in any elemental ward -- Endure Elements, Resist Elements,
//     Protection from Elements, Energy Buffer, or Elemental Shield
//     (QRDD_BloodIsWarded, GetHasSpellEffect) -- the attempt fails with a
//     flavor message and nothing is granted. Retry allowed -- let the
//     ward lapse or dispel it and use the forge again. Deterministic:
//     no dice.
//   * Unwarded at stage 1: gives the Ember of the Old Wyrm, stage 1 -> 2
//     + journal 2. At stage 2 with the ember lost, re-gives it (never
//     duplicates -- GetItemPossessedBy guard; the item is plot + cursed
//     and only the finish consumes it).
//
// Does nothing for PCs not on the rite (a quiet flavor line only).
#include "q_rdd_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QRDD_GetStage(oPC);
    if (nStage < QRDD_STAGE_ACCEPTED || nStage > QRDD_STAGE_EMBER)
    {
        FloatingTextStringOnCreature(
            "The Forge of Durin. Deep under the banked coals something "
            + "still glows -- a red older than any fire the dwarves ever lit.",
            oPC, FALSE);
        return;
    }
    if (QRDD_HasEmber(oPC)) return;

    // The fail condition: come to the coals behind a ward and the fire
    // does not know you. The blood must feel the flame.
    if (QRDD_BloodIsWarded(oPC))
    {
        FloatingTextStringOnCreature(
            "You reach for the coals and the old red light sinks away from "
            + "your warded hand -- the fire does not know you through it. "
            + "Shed every ward against the elements and reach in bare: the "
            + "blood must feel the flame.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QRDD_EMBER_RES, oPC, 1);

    if (nStage == QRDD_STAGE_ACCEPTED)
    {
        QRDD_SetStage(oPC, QRDD_STAGE_EMBER);
        AddJournalQuestEntry(QRDD_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "Heat rolls up your arm and through it -- and does not burn. From "
        + "under the banked coals your bare hand closes on an ember that "
        + "beats like a second heart: the old wyrm's fire, and it knows "
        + "your blood.",
        oPC, FALSE);
}
