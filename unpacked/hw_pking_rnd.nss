// hw_pking_rnd - Pumpkin King end-of-round: every third round he raises three
// cursed pumpkins around himself (which feed the attack aura around him) and
// calls up a band of skeletons exactly as a smashed pumpkin does (Power Word
// Kill burst, 1-3 skeletons scaled to the area tier or his foe, whichever is
// higher, sent at that foe). Then the stock combat round runs.

#include "hw_inc"

void main()
{
    object oKing = OBJECT_SELF;
    int n = GetLocalInt(oKing, "hw_round") + 1;
    SetLocalInt(oKing, "hw_round", n);
    if (n % 3 == 0 && HW_Phase() == HW_PHASE_ACTIVE)
    {
        location lKing = GetLocation(oKing);
        int i;
        for (i = 0; i < 3; i++)
        {
            object oPk = HW_SpawnPumpkin(HW_Scatter(lKing, 2.0, 6.0), "cursed");
            if (GetIsObjectValid(oPk))
                ApplyEffectToObject(DURATION_TYPE_INSTANT,
                    EffectVisualEffect(VFX_IMP_PULSE_FIRE), oPk);
        }

        object oFoe = GetAttackTarget(oKing);
        if (!GetIsObjectValid(oFoe)) oFoe = GetAttemptedAttackTarget();
        if (!GetIsObjectValid(oFoe))
            oFoe = GetNearestCreature(CREATURE_TYPE_PLAYER_CHAR, PLAYER_CHAR_IS_PC, oKing);
        location lSkel = HW_Scatter(lKing, 3.0, 6.0);
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_PWKILL), lSkel);
        HW_SpawnSkeletons(lSkel, HW_AreaTier(GetResRef(GetArea(oKing))), oFoe, 1 + Random(3));

        SpeakString("Grow, my pretties! Rise!");
    }
    ExecuteScript("x2_def_endcombat", oKing);
}
