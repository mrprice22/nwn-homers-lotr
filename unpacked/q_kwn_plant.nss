// q_kwn_plant - banner-stone OnUsed (roadmap: knight-westernesse-quest).
// A knight carrying the released standard (stage 4) sets the banner of
// the West in the old socket with their own hand: stage 4 -> 5, journal
// entry 5, a flare of the holy host for the field to see. Everyone else
// gets flavor. Per-PC, so the shared placeable never changes state.
#include "q_kwn_inc"

void main()
{
    object oStone = OBJECT_SELF;
    object oPC    = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QKWN_GetStage(oPC);

    if (nStage == QKWN_STAGE_STANDARD)
    {
        QKWN_SetStage(oPC, QKWN_STAGE_PLANTED);
        AddJournalQuestEntry(QKWN_QUEST, 5, oPC, FALSE, FALSE);

        ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_LOS_HOLY_10), GetLocation(oStone));
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_GOOD_HELP), oPC);
        FloatingTextStringOnCreature(
            "You set the banner of the West in the old socket, and the wind "
            + "off the River takes it. Halmir at the Well of Eru should hear "
            + "of this.", oPC, FALSE);
        return;
    }

    if (nStage >= QKWN_STAGE_PLANTED)
    {
        FloatingTextStringOnCreature(
            "The banner of the West flies here by your hand.", oPC, FALSE);
        return;
    }

    FloatingTextStringOnCreature(
        "An old socket-stone of the out-wall. Whatever standard it once "
        + "bore is long gone.", oPC, FALSE);
}
