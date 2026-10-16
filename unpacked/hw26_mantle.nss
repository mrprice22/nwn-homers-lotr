// hw26_mantle - Mantle of the Last Harvest: Scarecrow's Vigil (activated).
//
// 1 use per 90 real minutes. Summons a Scarecrow Sentinel for one real hour,
// scaled to the wearer's level (it takes the summon slot - the trade-off).
// When it falls it bursts, healing the wearer's party (hw_sent_death).

#include "hw_inc"

void HW_ScaleSentinel(object oPC)
{
    object oS = GetAssociate(ASSOCIATE_TYPE_SUMMONED, oPC);
    if (!GetIsObjectValid(oS) || GetTag(oS) != "hw_sentinel") return;
    int nHD = GetHitDice(oPC);
    effect e = EffectLinkEffects(EffectTemporaryHitpoints(nHD * 40),
               EffectLinkEffects(EffectACIncrease(nHD / 3),
               EffectLinkEffects(EffectAbilityIncrease(ABILITY_STRENGTH, nHD / 5),
                                 EffectSavingThrowIncrease(SAVING_THROW_ALL, nHD / 4))));
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, SupernaturalEffect(e), oS);
    // Attack through the ledger, same source as every other summon boost.
    BPool_Set(oS, BPOOL_CH_ATTACK, BPOOL_SRC_SUMMON, nHD / 2);
    SetObjectVisualTransform(oS, OBJECT_VISUAL_TRANSFORM_SCALE, 1.2);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(EffectVisualEffect(VFX_DUR_GLOW_LIGHT_ORANGE)), oS);
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "vigil", "Scarecrow's Vigil", 1)) return;
    ApplyEffectAtLocation(DURATION_TYPE_TEMPORARY,
        EffectSummonCreature("hw_sentinel", VFX_FNF_SUMMON_UNDEAD), GetLocation(oPC), 3600.0);
    DelayCommand(1.5, HW_ScaleSentinel(oPC));
}
