// q_dvc_altar -- the Divine Champions' vigil altar (roadmap:
// divine-champion-quest). OnUsed of the Altar of the Istari in the temple
// of Minas Tirith (minastirithtemp.git.json, existing placed instance 0
// reused -- retagged DvcVigilAltar; it was already usable + plot with no
// scripts, so there is nothing to chain, and no code referenced the old
// tag "AltarShrineGood"). Runs the stand-between vigil for a PC on the
// rite:
//
//   * The stand-between fail condition: come to the altar with the
//     off-hand arm bare, or with anything but a shield riding it
//     (QDVC_IsShieldBorne -- GetItemInSlot(INVENTORY_SLOT_LEFTHAND) must
//     be a small/large/tower shield), and the attempt fails with a flavor
//     message; nothing is granted. Retry allowed -- take up a shield and
//     keep the vigil again. Deterministic: the shield is the test,
//     no dice.
//   * Shield borne at stage 1: gives the oath-light, stage 1 -> 2 +
//     journal 2. At stage 2 with the light lost, re-gives it (never
//     duplicates -- GetItemPossessedBy guard; the item is plot + cursed
//     and only the finish consumes it).
//
// Does nothing for PCs not on the rite -- to everyone else it is just the
// temple's polished altar.
#include "q_dvc_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QDVC_GetStage(oPC);
    if (nStage < QDVC_STAGE_ACCEPTED || nStage > QDVC_STAGE_LIGHT) return;
    if (QDVC_HasLight(oPC)) return;

    // The fail conditions: a bare arm, or something that takes where the
    // shield should ride. The altar keeps its light from both.
    object oOff = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    if (!GetIsObjectValid(oOff))
    {
        FloatingTextStringOnCreature(
            "You lay your hand on the polished stone, and the altar keeps "
            + "its light. The champion's vow is not to strike harder -- it "
            + "is to stand between. Take up a shield and keep the vigil as "
            + "the order keeps it.",
            oPC, FALSE);
        return;
    }
    if (!QDVC_IsShieldBorne(oPC))
    {
        FloatingTextStringOnCreature(
            "The altar's gleam goes flat where your shadow falls. "
            + "Something rides your arm where the shield should -- a thing "
            + "that takes, not a thing that stands between. Bear a shield "
            + "and keep the vigil again.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QDVC_LIGHT_RES, oPC, 1);

    if (nStage == QDVC_STAGE_ACCEPTED)
    {
        QDVC_SetStage(oPC, QDVC_STAGE_LIGHT);
        AddJournalQuestEntry(QDVC_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "The vigil is kept: shield on arm, and nothing in your keeping "
        + "that takes. Warmth gathers over the polished stone, and a small "
        + "flame comes away with your palm -- an oath-light, weightless "
        + "and steady, that does not gutter. Carry it to Halmir.",
        oPC, FALSE);
}
