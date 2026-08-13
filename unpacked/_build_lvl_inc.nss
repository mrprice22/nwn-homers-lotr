//::///////////////////////////////////////////////
//:: _build_lvl_inc
//:: Shared helper for the Ping Pong ("Ultimate PC Builder") level menu,
//:: legendary tier (levels 41 - 60).
//::
//:: The stock _build_level_1..40 scripts each hard-code a cumulative XP
//:: value from the old Bioware curve (500 * n * (n - 1); level 40 = 780000).
//:: Levels 41 - 60 do NOT follow that formula -- they come from the server's
//:: own experience table, hak_2da/exptable.2da, where the per-level delta
//:: starts at 48800 over the level-40 total and compounds by x1.1
//:: (level 41 = 828800 ... level 60 = 3581000).
//::
//:: So this helper reads exptable.2da directly at runtime -- one source of
//:: truth -- and only falls back to the transcribed values below if the 2da
//:: row cannot be read (e.g. the hak is not loaded, in which case levels
//:: past 40 do not exist in that game anyway).
//::
//:: Same convention as code_redeem.nss's XP_LEVEL_60: if the 41-60 curve is
//:: ever retuned in exptable.2da, the fallback table here must be retuned
//:: with it.
//:://////////////////////////////////////////////
#include "season_prof_inc"

// Cumulative XP required for character level nLevel (41 <= nLevel <= 60),
// or 0 if nLevel is outside that range.
int BuildLegendaryXP(int nLevel);

// Set oPC to exactly the cumulative XP for nLevel and play the usual
// Ping Pong "you have been levelled" flourish. No-op for a bad level.
void BuildSetLegendaryLevel(int nLevel);


int BuildLegendaryXP(int nLevel)
{
    if (nLevel < 41 || nLevel > 60) return 0;

    // exptable.2da is 0-indexed by (level - 1): row 40 -> level 41.
    string sXP = Get2DAString("exptable", "XP", nLevel - 1);
    int nXP = StringToInt(sXP);
    if (nXP > 0) return nXP;

    // Fallback: transcribed from hak_2da/exptable.2da rows 40 - 59.
    switch (nLevel)
    {
        case 41: return  828800;
        case 42: return  882500;
        case 43: return  941600;
        case 44: return 1006600;
        case 45: return 1078100;
        case 46: return 1156800;
        case 47: return 1243400;
        case 48: return 1338700;
        case 49: return 1443500;
        case 50: return 1558800;
        case 51: return 1685600;
        case 52: return 1825100;
        case 53: return 1978600;
        case 54: return 2147500;
        case 55: return 2333300;
        case 56: return 2537700;
        case 57: return 2762500;
        case 58: return 3009800;
        case 59: return 3281800;
        case 60: return 3581000;
    }
    return 0;
}

void BuildSetLegendaryLevel(int nLevel)
{
    // Belt and braces. onmoduleload destroys the Ping Pong NPC outright where
    // SP_DEV_TOOLS is off, so this should be unreachable in production - but
    // "should be unreachable" is doing a lot of work for a function that sets a
    // character to level 60, and a DM-spawned copy of the NPC or a stray
    // reference to this dialog would route straight here. All 20 legendary
    // _build_level_* scripts funnel through this one function, so one guard
    // covers the whole tier.
    if (!SP_DEV_TOOLS) return;

    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) return;

    int nXP = BuildLegendaryXP(nLevel);
    if (nXP <= 0)
    {
        SendMessageToPC(oPC, "Ping Pong: that legendary level is not on the "
                             + "experience table.");
        return;
    }

    object oCaster = OBJECT_SELF;
    effect eVFX = EffectVisualEffect(VFX_IMP_HASTE);

    // Note: the stock _build_level_* scripts drive the flourish off
    // GetLastSpeaker() but set XP on GetPCSpeaker(). Use GetPCSpeaker() for
    // both so the effect always lands on the player who picked the reply.
    DelayCommand(0.0, AssignCommand(oCaster,
        ActionCastFakeSpellAtObject(SPELL_MASS_HEAL, oPC)));
    DelayCommand(2.0, ApplyEffectToObject(DURATION_TYPE_INSTANT, eVFX, oPC));
    DelayCommand(2.0, FloatingTextStringOnCreature(
        "LEGENDARY LEVEL " + IntToString(nLevel), oPC));

    SetXP(oPC, nXP);
}
