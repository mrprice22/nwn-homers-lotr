// hw26_pail - the Bottomless Pumpkin Pail: trick or treat, once per real hour.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "pail", "The Bottomless Pail", 1, 3600)) return;

    int r = Random(100);
    string sMsg;
    if (r < 25)
    {
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(GetMaxHitPoints(oPC)), oPC);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_HEALING_X), oPC);
        sMsg = "Treat! A sweet that mends every hurt.";
    }
    else if (r < 45)
    {
        effect e = EffectLinkEffects(EffectAbilityIncrease(ABILITY_STRENGTH, 4),
                   EffectLinkEffects(EffectAbilityIncrease(ABILITY_DEXTERITY, 4),
                   EffectLinkEffects(EffectAbilityIncrease(ABILITY_CONSTITUTION, 4),
                   EffectLinkEffects(EffectAbilityIncrease(ABILITY_INTELLIGENCE, 4),
                   EffectLinkEffects(EffectAbilityIncrease(ABILITY_WISDOM, 4),
                                     EffectAbilityIncrease(ABILITY_CHARISMA, 4))))));
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, e, oPC, 3600.0);
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, EffectTemporaryHitpoints(20), oPC, 3600.0);
        sMsg = "Treat! A candied apple: +4 to every ability for an hour.";
    }
    else if (r < 60)
    {
        int nGold = 25000 + Random(75001);
        GiveGoldToCreature(oPC, nGold);
        sMsg = "Treat! " + IntToString(nGold) + " gold, sticky with caramel.";
    }
    else if (r < 75)
    {
        string sGem;
        switch (Random(6))
        {
            case 0: sGem = "nw_it_gem006"; break;
            case 1: sGem = "nw_it_gem009"; break;
            case 2: sGem = "nw_it_gem010"; break;
            case 3: sGem = "nw_it_gem011"; break;
            case 4: sGem = "nw_it_gem012"; break;
            default: sGem = "nw_it_gem013"; break;
        }
        CreateItemOnObject(sGem, oPC);
        sMsg = "Treat! A gem at the bottom of the pail.";
    }
    else if (r < 85)
    {
        CreateItemOnObject("nw_it_mpotion012", oPC, 5);
        sMsg = "Treat! Five potions, still warm.";
    }
    else if (r < 95)
    {
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, EffectPolymorph(POLYMORPH_TYPE_CHICKEN), oPC, 30.0);
        sMsg = "TRICK! Bawk.";
    }
    else
    {
        HW_SpawnSkeletons(GetLocation(oPC), HW_AreaTier(GetResRef(GetArea(oPC))), oPC, 1);
        sMsg = "TRICK! Something climbs out of the pail.";
    }
    FloatingTextStringOnCreature(sMsg, oPC, TRUE);
}
