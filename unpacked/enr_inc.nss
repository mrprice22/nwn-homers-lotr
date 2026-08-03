// enr_inc - boss enrage-on-retreat (roadmap: boss-enrage-on-retreat).
//
// Design spec: docs.manual/boss-updates.html#enrage.
//
// Scope: ONLY the CR>60 single-instance bosses on the Roll-of-the-Fallen
// registry (respawndb.boss_registry, seeded from brd_db.nss). When a PC who
// has been fighting such a boss disengages - leaves the area, moves out of
// engagement range, or logs out, whether or not other PCs are still fighting -
// the boss:
//   1. shouts a taunt naming the fleeing player (shout channel),
//   2. gains +2 to ALL ability scores for the remainder of that life
//      (supernatural + permanent: undispellable, stacks per retreat, and can
//      never carry onto a respawn because a respawn is a fresh creature), and
//   3. instantly heals 25% of its missing HP.
//
// "Left combat" detection (the open design detail in the brief): a hybrid of
// the two candidates, built on plumbing that already exists -
//   * ENGAGEMENT is recorded by the bestiary's runtime OnDamaged wrapper
//     (bst_ondamage calls ENR_OnBossDamaged with the master-chain-resolved
//     owning PC), so anyone who damages the boss - melee, ranged, caster, or
//     via summons/henchmen - is "engaged". No new event hooks needed.
//   * DISENGAGEMENT is decided by a boss-side pseudo-heartbeat (a DelayCommand
//     loop that only runs while at least one PC is engaged - zero cost for the
//     other 500+ creatures and for idle bosses). Each tick, an engaged PC who
//     is out of the boss's area, farther than ENR_RANGE, or logged out gets a
//     strike; ENR_STRIKES consecutive strikes (~ENR_TICK * ENR_STRIKES
//     seconds) = disengaged. Any new damage from that PC resets the strikes,
//     so a long-range archer/caster past ENR_RANGE stays engaged as long as
//     they keep contributing. Dying is NOT retreating: a dead engaged PC is
//     dropped silently with no enrage.
//
// This deliberately complements leash_to_area: the leash sends a kited boss
// home but never heals it; enrage-on-retreat closes that attrition gap and
// also covers within-area retreats the leash never sees.
//
// Defensive by construction: not-a-registry-boss no-ops (cached, one SQL
// lookup per creature life), invalid objects no-op, the tick loop dies with
// the boss, and nothing here touches placed content.
//
// Locals used (all on the boss, so they vanish with the corpse):
//   int    enr_isboss     registry check cache: 0 unknown, 1 boss, -1 not
//   int    enr_n          number of engaged entries
//   object enr_pc_<i>     engaged PC
//   string enr_name_<i>   PC first name, captured at engage (survives logout)
//   int    enr_out_<i>    consecutive out-of-range strikes
//   int    enr_ticking    guard: the pseudo-heartbeat loop is scheduled
//   int    enr_stacks     enrage stacks applied this life (debug/telemetry)

#include "brd_db"

const float ENR_RANGE   = 40.0;  // metres; past this (or out of area) = retreating
const float ENR_TICK    = 6.0;   // seconds between disengage scans
const int   ENR_STRIKES = 2;     // consecutive out-of-range ticks = disengaged

// TRUE when oCre is on the Roll-of-the-Fallen boss registry. One campaign-DB
// lookup per creature life, cached in a local.
int ENR_IsRegistryBoss(object oCre)
{
    int nCache = GetLocalInt(oCre, "enr_isboss");
    if (nCache != 0) return (nCache == 1);

    string sRef = BRD_Canonical(GetResRef(oCre));
    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT 1 FROM boss_registry WHERE resref=@r");
    SqlBindString(q, "@r", sRef);
    int bBoss = SqlStep(q);

    SetLocalInt(oCre, "enr_isboss", bBoss ? 1 : -1);
    return bBoss;
}

// First word of the PC's name, for the taunt.
string ENR_FirstName(object oPC)
{
    string sName = GetName(oPC);
    int nSpace = FindSubString(sName, " ");
    if (nSpace > 0) return GetStringLeft(sName, nSpace);
    return sName;
}

// Apply one enrage stack: taunt, +2 all abilities for this life, heal 25%
// of missing HP.
void ENR_TriggerEnrage(object oBoss, string sFleeingName)
{
    if (!GetIsObjectValid(oBoss) || GetIsDead(oBoss)) return;

    if (sFleeingName == "") sFleeingName = "coward";
    AssignCommand(oBoss, SpeakString(
        "Fool, " + sFleeingName + ", my power only grows as you retreat.",
        TALKVOLUME_SHOUT));

    // +2 to all six ability scores, supernatural (undispellable) + permanent:
    // lasts exactly this life, stacks per retreat, gone on respawn.
    effect eBuff = EffectAbilityIncrease(ABILITY_STRENGTH, 2);
    eBuff = EffectLinkEffects(eBuff, EffectAbilityIncrease(ABILITY_DEXTERITY,    2));
    eBuff = EffectLinkEffects(eBuff, EffectAbilityIncrease(ABILITY_CONSTITUTION, 2));
    eBuff = EffectLinkEffects(eBuff, EffectAbilityIncrease(ABILITY_INTELLIGENCE, 2));
    eBuff = EffectLinkEffects(eBuff, EffectAbilityIncrease(ABILITY_WISDOM,       2));
    eBuff = EffectLinkEffects(eBuff, EffectAbilityIncrease(ABILITY_CHARISMA,     2));
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, SupernaturalEffect(eBuff), oBoss);

    // Heal 25% of missing HP.
    int nMissing = GetMaxHitPoints(oBoss) - GetCurrentHitPoints(oBoss);
    if (nMissing > 0)
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(nMissing / 4), oBoss);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_IMPROVE_ABILITY_SCORE), oBoss);

    SetLocalInt(oBoss, "enr_stacks", GetLocalInt(oBoss, "enr_stacks") + 1);
}

// Remove engaged entry i by moving the last entry into its slot.
void ENR_RemoveEntry(object oBoss, int i, int nN)
{
    int nLast = nN - 1;
    if (i != nLast)
    {
        SetLocalObject(oBoss, "enr_pc_"   + IntToString(i),
            GetLocalObject(oBoss, "enr_pc_"   + IntToString(nLast)));
        SetLocalString(oBoss, "enr_name_" + IntToString(i),
            GetLocalString(oBoss, "enr_name_" + IntToString(nLast)));
        SetLocalInt   (oBoss, "enr_out_"  + IntToString(i),
            GetLocalInt   (oBoss, "enr_out_"  + IntToString(nLast)));
    }
    DeleteLocalObject(oBoss, "enr_pc_"   + IntToString(nLast));
    DeleteLocalString(oBoss, "enr_name_" + IntToString(nLast));
    DeleteLocalInt   (oBoss, "enr_out_"  + IntToString(nLast));
    SetLocalInt(oBoss, "enr_n", nLast);
}

// The disengage scan. Reschedules itself while anyone is engaged; the loop
// (and every local it reads) dies with the boss, so enrage never persists
// onto a respawned instance.
void ENR_Tick(object oBoss)
{
    if (!GetIsObjectValid(oBoss) || GetIsDead(oBoss)) return;

    object oBossArea = GetArea(oBoss);
    int nN = GetLocalInt(oBoss, "enr_n");
    int i = 0;
    while (i < nN)
    {
        string sI  = IntToString(i);
        object oPC = GetLocalObject(oBoss, "enr_pc_" + sI);

        int bDropSilent = FALSE;   // remove without enrage (death)
        int bOut        = FALSE;   // this tick counts as a strike

        if (!GetIsObjectValid(oPC))
            bOut = TRUE;                       // logged out / gone = retreating
        else if (GetIsDead(oPC))
            bDropSilent = TRUE;                // dying is not retreating
        else if (GetArea(oPC) != oBossArea
              || GetDistanceBetween(oBoss, oPC) > ENR_RANGE)
            bOut = TRUE;

        if (bDropSilent)
        {
            ENR_RemoveEntry(oBoss, i, nN);
            nN--;
            continue;                          // re-check the swapped-in entry
        }

        if (bOut)
        {
            int nStrikes = GetLocalInt(oBoss, "enr_out_" + sI) + 1;
            if (nStrikes >= ENR_STRIKES)
            {
                ENR_TriggerEnrage(oBoss, GetLocalString(oBoss, "enr_name_" + sI));
                ENR_RemoveEntry(oBoss, i, nN);
                nN--;
                continue;
            }
            SetLocalInt(oBoss, "enr_out_" + sI, nStrikes);
        }
        else
            SetLocalInt(oBoss, "enr_out_" + sI, 0);

        i++;
    }

    if (nN > 0)
        DelayCommand(ENR_TICK, ENR_Tick(oBoss));
    else
        SetLocalInt(oBoss, "enr_ticking", 0);
}

// Entry point, called from bst_ondamage with the master-chain-resolved owning
// PC. OBJECT_SELF is the damaged creature. No-ops for anything that isn't a
// registry boss.
void ENR_OnBossDamaged(object oCre, object oPC)
{
    if (!GetIsObjectValid(oCre) || GetIsDead(oCre)) return;
    if (!GetIsObjectValid(oPC)) return;
    if (!ENR_IsRegistryBoss(oCre)) return;

    // Already engaged? Refresh: damage proves they're still in the fight.
    int nN = GetLocalInt(oCre, "enr_n");
    int i;
    for (i = 0; i < nN; i++)
    {
        if (GetLocalObject(oCre, "enr_pc_" + IntToString(i)) == oPC)
        {
            SetLocalInt(oCre, "enr_out_" + IntToString(i), 0);
            return;
        }
    }

    // New engagement (or re-engagement after a previous retreat - which can
    // legitimately earn the boss another stack later).
    string sN = IntToString(nN);
    SetLocalObject(oCre, "enr_pc_"   + sN, oPC);
    SetLocalString(oCre, "enr_name_" + sN, ENR_FirstName(oPC));
    SetLocalInt   (oCre, "enr_out_"  + sN, 0);
    SetLocalInt   (oCre, "enr_n", nN + 1);

    if (!GetLocalInt(oCre, "enr_ticking"))
    {
        SetLocalInt(oCre, "enr_ticking", 1);
        DelayCommand(ENR_TICK, ENR_Tick(oCre));
    }
}
