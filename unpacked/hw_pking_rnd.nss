// hw_pking_rnd - Pumpkin King end-of-round.
//
// * Sacrifice: below 80% HP, at most once per 40s, he drains a Pumpkin-Born
//   Skeleton standing within 10m - its soul streams into him (ghost visage and
//   smoke on the skeleton, an evil beam to the King), the husk crumbles and he
//   heals 15% of his max HP. Not a kill: no guts, no pumpkin.
// * Every third round he raises three cursed pumpkins around himself (which
//   feed the attack aura around him) and calls up a band of skeletons exactly
//   as a smashed pumpkin does (Power Word Kill burst, 1-3 skeletons scaled to
//   the area tier or his foe, whichever is higher, sent at that foe).
// * Idle skeletons of his army within 20m are sent at his foe.
// Then the stock combat round runs.

#include "hw_inc"
#include "season_prof_inc"

void HW_SacrificeFinish(object oKing, object oSk)
{
    if (GetIsObjectValid(oSk))
    {
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_DEATH_L), GetLocation(oSk));
        SetCommandable(TRUE, oSk);
        DestroyObject(oSk, 0.2);
    }
    if (!GetIsObjectValid(oKing) || GetIsDead(oKing)) return;
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectHeal(GetMaxHitPoints(oKing) * HW_SAC_HEAL_PCT / 100), oKing);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_HEALING_G), oKing);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_EVIL_HELP), oKing);
}

string HW_SacrificeLine()
{
    switch (Random(4))
    {
        case 0: return "Your bones are mine to spend.";
        case 1: return "Give me your light, little one.";
        case 2: return "Back into the patch with you - and your strength into me!";
    }
    return "Every harvest ends in the King's belly.";
}

// Returns "" at 80%+ HP (nothing to report), otherwise what happened and why.
string HW_TrySacrifice(object oKing)
{
    int nMax = GetMaxHitPoints(oKing);
    if (nMax <= 0) return "";
    int nPct = GetCurrentHitPoints(oKing) * 100 / nMax;
    if (nPct >= HW_SAC_BELOW_PCT) return "";
    string sHp = "HP " + IntToString(nPct) + "%: ";
    int nNow = HW_Now();
    int nWait = HW_SAC_EVERY - (nNow - GetLocalInt(oKing, "hw_sac_at"));
    if (nWait > 0) return sHp + "sacrifice cooling down, " + IntToString(nWait) + "s left";

    int n = 1;
    object oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, n);
    while (GetIsObjectValid(oSk) && GetIsDead(oSk))
        oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, ++n);
    if (!GetIsObjectValid(oSk)) return sHp + "no living skeleton in the area";
    float fDist = GetDistanceBetween(oSk, oKing);
    if (fDist > 10.0)
        return sHp + "nearest skeleton is " + IntToString(FloatToInt(fDist)) + "m away (needs 10m)";

    SetLocalInt(oKing, "hw_sac_at", nNow);
    SpeakString(HW_SacrificeLine(), TALKVOLUME_TALK);

    AssignCommand(oSk, ClearAllActions(TRUE));
    SetCommandable(FALSE, oSk);
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
        EffectVisualEffect(VFX_DUR_GHOSTLY_VISAGE_NO_SOUND), oSk, 2.0);
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
        EffectVisualEffect(VFX_DUR_GHOST_SMOKE_2), oSk, 2.0);
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
        EffectBeam(VFX_BEAM_EVIL, oSk, BODY_NODE_CHEST), oKing, 2.0);
    DelayCommand(1.5, HW_SacrificeFinish(oKing, oSk));
    return sHp + "SACRIFICED a skeleton";
}

void main()
{
    object oKing = OBJECT_SELF;
    if (HW_Phase() == HW_PHASE_ACTIVE)
    {
        string sWhy = HW_TrySacrifice(oKing);
        if (SP_DEV_TOOLS && sWhy != "")
        {
            object oArea = GetArea(oKing);
            object oPC = GetFirstPC();
            while (GetIsObjectValid(oPC))
            {
                if (GetArea(oPC) == oArea) SendMessageToPC(oPC, "[HW dev] King " + sWhy);
                oPC = GetNextPC();
            }
        }
    }

    object oFoe = GetAttackTarget(oKing);
    if (!GetIsObjectValid(oFoe)) oFoe = GetAttemptedAttackTarget();
    if (!GetIsObjectValid(oFoe))
        oFoe = GetNearestCreature(CREATURE_TYPE_PLAYER_CHAR, PLAYER_CHAR_IS_PC, oKing);

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

        location lSkel = HW_Scatter(lKing, 3.0, 6.0);
        ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_PWKILL), lSkel);
        HW_SpawnSkeletons(lSkel, HW_AreaTier(GetResRef(GetArea(oKing))), oFoe, 1 + Random(3));

        SpeakString("Grow, my pretties! Rise!");
    }

    // His army joins the fight.
    if (GetIsObjectValid(oFoe))
    {
        int k = 1;
        object oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, k);
        while (GetIsObjectValid(oSk) && GetDistanceBetween(oSk, oKing) <= 20.0)
        {
            if (!GetIsDead(oSk) && GetCommandable(oSk)
                && !GetIsObjectValid(GetAttackTarget(oSk)))
            {
                AssignCommand(oSk, ClearAllActions());
                AssignCommand(oSk, ActionAttack(oFoe));
            }
            oSk = GetNearestObjectByTag(HW_TAG_SKEL, oKing, ++k);
        }
    }

    ExecuteScript("x2_def_endcombat", oKing);
}
