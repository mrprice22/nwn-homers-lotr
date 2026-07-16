// q_shd_well -- The Unlit Deep (roadmap: shadowdancer-quest).
// OnUsed of the Deep Well instance beside Balin's tomb
// (balinstomb.git.json, existing placed "DeepWell" reused). Keeps the
// instance's previous OnUsed (balintmb_dpwell, the stone-drop-and-splash
// sound flavor) by chaining it, then runs the Shadowdancers' trial for a
// PC on the rite:
//
//   * The torch-suppression fail condition: if the PC carries ANY light
//     (torch or light-property item equipped, or an active Light /
//     Continual Flame effect -- QSHD_CarriesLight), the attempt fails
//     with a flavor message and nothing is granted. Retry allowed --
//     douse the light and use the well again.
//   * Unlit at stage 1: gives the Skein of the Unlit Deep, stage 1 -> 2
//     + journal 2. At stage 2 with the skein lost, re-gives it (never
//     duplicates -- GetItemPossessedBy guard; the item is plot + cursed
//     and only the finish consumes it).
//
// Does nothing quest-side for PCs not on the rite (the well still
// splashes for everyone).
#include "q_shd_inc"

void main()
{
    // The well's previous OnUsed (sound flavor), unchanged for everyone.
    ExecuteScript("balintmb_dpwell", OBJECT_SELF);

    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QSHD_GetStage(oPC);
    if (nStage < QSHD_STAGE_ACCEPTED || nStage > QSHD_STAGE_SKEIN) return;
    if (QSHD_HasSkein(oPC)) return;

    // The fail condition: come to the well carrying light and the dark
    // closes its hand. Nothing granted; douse the light and try again.
    if (QSHD_CarriesLight(oPC))
    {
        FloatingTextStringOnCreature(
            "Light rides with you -- a torch, a glowing blade, a conjured flame -- "
            + "and the deep gives nothing to what it can see. Come to the well unlit.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QSHD_SKEIN_RES, oPC, 1);

    if (nStage == QSHD_STAGE_ACCEPTED)
    {
        QSHD_SetStage(oPC, QSHD_STAGE_SKEIN);
        AddJournalQuestEntry(QSHD_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "In darkness unbroken, something winds itself about your fingers -- "
        + "a skein of the unlit deep, like black thread spun on nothing.",
        oPC, FALSE);
}
