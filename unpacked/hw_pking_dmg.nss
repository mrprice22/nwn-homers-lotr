// hw_pking_dmg - Pumpkin King OnDamaged (chained by bst_ondamage, which wraps
// every creature's OnDamaged; the stock x2_def_ondamage runs at the end).
//
// Both of his fight mechanics run here, on real-time timers, rather than on
// OnEndCombatRound: that event only fires on rounds he actually takes, so a
// King held, stunned or knocked down by a level-60 player never sacrificed
// a skeleton even with fifteen standing round him.
//
// * Sacrifice: below 80% HP, at most once per 40s, he drains a Pumpkin-Born
//   Skeleton within 10m - its soul streams into him (ghost visage and smoke on
//   the skeleton, an evil beam to the King), the husk crumbles and he heals
//   HW_SAC_HEAL_PCT of his max HP. Not a kill: no guts, no pumpkin. In the
//   Final Harvest (HW_Final) it is once per 20s and heals him to full.
// * Harvest: every 18s of being fought he raises three cursed pumpkins round
//   himself and calls up a band of skeletons exactly as a smashed pumpkin
//   does (Power Word Kill burst, 1-3 skeletons scaled to the area tier or his
//   attacker, whichever is higher, sent at that attacker). 2-6 in the Final
//   Harvest.
//
// Test realms (SP_DEV_TOOLS) print what the sacrifice did and why, at most
// every 6s, to players in his area.

#include "hw_inc"
#include "season_prof_inc"

const int HW_HARVEST_EVERY = 18;   // seconds; three combat rounds

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
    int nHeal = HW_Final() ? GetMaxHitPoints(oKing)
                           : GetMaxHitPoints(oKing) * HW_SAC_HEAL_PCT / 100;
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(nHeal), oKing);
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
    int nWait = HW_SacEvery() - (nNow - GetLocalInt(oKing, "hw_sac_at"));
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

void HW_Harvest(object oKing, object oFoe)
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
    int nBand = HW_Final() ? 2 + Random(5) : 1 + Random(3);
    HW_SpawnSkeletons(lSkel, HW_AreaTier(GetResRef(GetArea(oKing))), oFoe, nBand);
    SpeakString("Grow, my pretties! Rise!");
}

void main()
{
    object oKing = OBJECT_SELF;
    if (HW_Phase() == HW_PHASE_ACTIVE && !GetIsDead(oKing))
    {
        int nNow = HW_Now();

        string sWhy = HW_TrySacrifice(oKing);
        if (SP_DEV_TOOLS && sWhy != ""
            && (FindSubString(sWhy, "SACRIFICED") >= 0
                || nNow - GetLocalInt(oKing, "hw_sac_dbg_at") >= 6))
        {
            SetLocalInt(oKing, "hw_sac_dbg_at", nNow);
            object oArea = GetArea(oKing);
            object oPC = GetFirstPC();
            while (GetIsObjectValid(oPC))
            {
                if (GetArea(oPC) == oArea) SendMessageToPC(oPC, "[HW dev] King " + sWhy);
                oPC = GetNextPC();
            }
        }

        // The first blow starts the clock; a harvest every 18s after that.
        int nLast = GetLocalInt(oKing, "hw_harvest_at");
        if (nLast == 0)
            SetLocalInt(oKing, "hw_harvest_at", nNow);
        else if (nNow - nLast >= HW_HARVEST_EVERY)
        {
            SetLocalInt(oKing, "hw_harvest_at", nNow);
            object oFoe = GetLastDamager(oKing);
            while (GetIsObjectValid(GetMaster(oFoe))) oFoe = GetMaster(oFoe);
            HW_Harvest(oKing, oFoe);
        }
    }
    ExecuteScript("x2_def_ondamage", oKing);
}
