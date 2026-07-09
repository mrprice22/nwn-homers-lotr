//::///////////////////////////////////////////////
//:: horn_summon -- summon the Fell Beast companion from the
//:: "Horn of the Fell Beast" (tag HornFellBeast), dispatched by
//:: dmfi_activate's OnActivateItem branch. OBJECT_SELF / oPC is the
//:: activator (passed from dmfi_activate as oActivator).
//::
//:: Rules (per design):
//::   * Per-character, once per REAL hour, the clock RESETTING on each
//::     successful summon. Death/dismissal does NOT shortcut it.
//::   * Only one Fell Beast companion out at a time.
//::
//:: Cooldown is stored as the last-summon unix epoch in the "fellbeast"
//:: campaign DB, scoped to the PC (same per-character persistence the
//:: MeaningWave guides use). "Now" comes from SQLite strftime, the same
//:: wall-clock source brd_db.nss uses.
//:://////////////////////////////////////////////

const string FB_DB       = "fellbeast";
const string FB_HENCH_TAG = "fellbeast_h";
const int    FB_COOLDOWN  = 3600; // seconds (1 real hour)

// Current wall-clock epoch seconds (server real time).
int FB_Now()
{
    sqlquery q = SqlPrepareQueryObject(GetModule(), "SELECT strftime('%s','now');");
    if (SqlStep(q))
        return SqlGetInt(q, 0);
    return 0;
}

// Remove any Fell Beast this PC already has out (mirrors MW_DismissActiveGuide).
void FB_DismissExisting(object oPC)
{
    int i;
    for (i = 1; i <= 5; i++)
    {
        object oH = GetHenchman(oPC, i);
        if (!GetIsObjectValid(oH)) break;
        if (GetTag(oH) == FB_HENCH_TAG)
        {
            RemoveHenchman(oPC, oH);
            AssignCommand(oH, ClearAllActions());
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oH);
        }
    }
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // --- Cooldown gate (reset on each successful summon) ---
    int nNow  = FB_Now();
    int nLast = GetCampaignInt(FB_DB, "last_summon", oPC);
    int nLeft = FB_COOLDOWN - (nNow - nLast);
    if (nLast > 0 && nNow > 0 && nLeft > 0)
    {
        int nMin = (nLeft + 59) / 60; // round up to whole minutes
        FloatingTextStringOnCreature(
            "The horn is spent. The Fell Beast will not answer again for " +
            IntToString(nMin) + " more minute" + (nMin == 1 ? "" : "s") + ".",
            oPC, FALSE);
        return;
    }

    // --- Summon (one at a time) ---
    FB_DismissExisting(oPC);

    object oBeast = CreateObject(OBJECT_TYPE_CREATURE, "fellbeast_h",
                                 GetLocation(oPC));
    if (!GetIsObjectValid(oBeast))
    {
        FloatingTextStringOnCreature(
            "The horn sounds, but nothing comes (blueprint fellbeast_h missing).",
            oPC, FALSE);
        return;
    }

    AddHenchman(oPC, oBeast);
    if (GetMaster(oBeast) != oPC)
    {
        // AddHenchman refused -- almost always the henchman cap. Tell the player
        // rather than leaving an orphaned, unbound beast standing around.
        FloatingTextStringOnCreature(
            "You already lead as many companions as you can. Dismiss one, then " +
            "sound the horn again.", oPC, FALSE);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oBeast);
        return;
    }

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_SUMMON_MONSTER_3), oBeast);

    // Start (reset) the cooldown only on a fully successful summon.
    SetCampaignInt(FB_DB, "last_summon", nNow, oPC);
}
