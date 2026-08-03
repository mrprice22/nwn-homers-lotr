// q_maz_use - seal-brazier OnUsed (roadmap: twentieth-plot-mazarbul)
// Light a crypt-seal brazier: once per PC per brazier, persistent (campaign
// DB "maz20" keys seal_1..3 - relog/restart-safe). Lighting grants a short
// ward against grave-chill (minor negative-energy resistance, pure flavor).
// The third seal completes the rite and raises the Wraith of the Twentieth
// Plot. Completability guard: at stage 2 a brazier re-summons the wraith if
// none is alive (someone else landed the kill, or the PC fell and returned),
// so the fight can always be re-staged. Single-spawn guarded throughout.
#include "q_maz_inc"

void main()
{
    object oBraz = OBJECT_SELF;
    object oPC   = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = MAZ_GetStage(oPC);

    if (nStage == 0)
    {
        FloatingTextStringOnCreature(
            "The brazier is cold and will not take a flame. The restless "
            + "shade in the Chamber of Records knows its purpose.", oPC, FALSE);
        return;
    }

    if (nStage == 1)
    {
        int nIdx = GetLocalInt(oBraz, "q_maz_idx");
        if (MAZ_HasSeal(oPC, nIdx))
        {
            FloatingTextStringOnCreature(
                "This seal-brazier already burns for you.", oPC, FALSE);
            return;
        }

        MAZ_SetSeal(oPC, nIdx);
        int nSeals = MAZ_CountSeals(oPC);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_HEAD_HOLY), oPC);
        // Grave-chill ward: minor, temporary, flavor only.
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
            SupernaturalEffect(EffectDamageResistance(DAMAGE_TYPE_NEGATIVE, 5)),
            oPC, 300.0);
        FloatingTextStringOnCreature("The seal-brazier flares with pale fire ("
            + IntToString(nSeals) + " of "
            + IntToString(MAZ_BRAZIERS) + ").", oPC, FALSE);

        if (nSeals >= MAZ_BRAZIERS)
        {
            MAZ_SetStage(oPC, 2);
            AddJournalQuestEntry(MAZ_QUEST, 2, oPC, FALSE, FALSE);
            FloatingTextStringOnCreature(
                "The third seal is set -- and something shrieks in the deep!",
                oPC, FALSE);
            MAZ_SpawnWraith(oBraz);
        }
        return;
    }

    if (nStage == 2)
    {
        if (!MAZ_WraithAlive())
        {
            MAZ_SpawnWraith(oBraz);
            FloatingTextStringOnCreature(
                "The flame gutters -- the wraith returns to smother it!",
                oPC, FALSE);
        }
        else
        {
            FloatingTextStringOnCreature(
                "The wraith already walks -- destroy it!", oPC, FALSE);
        }
        return;
    }

    FloatingTextStringOnCreature(
        "The seal-fires burn steady over the twentieth plot.", oPC, FALSE);
}
