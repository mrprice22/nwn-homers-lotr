// enr_inc - boss enrage-on-retreat (roadmap: boss-enrage-on-retreat) and the
// out-of-combat reset that decays it (roadmap:
// add-a-decay-to-enrage-on-retreat-mechanic).
//
// Design spec: docs.manual/Draft/boss-updates.html#enrage.
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
// THE RESET (decay). Enrage stacks used to last the boss's whole life, so a
// party that chipped at a boss and walked away left the next player a boss
// that was stronger than its blueprint and already wounded. Now: once nobody
// is engaged, the boss arms a timer for its OWN registry respawn_seconds (the
// same wait a player would face had they killed it). If it is still out of
// combat when that expires, it is fully restored in place -
//   * every enrage stack removed (the effects are tagged ENR_EFFECT_TAG),
//   * ForceRest: full HP, spells and feats per day back,
//   * jumped home to its "spawn" location (the leash_to_area home),
//   * items looted/pickpocketed/consumed since the fight began re-created from
//     a snapshot taken the first time it was damaged this life, and
//   * a shout, so a player walking back in knows the fight has restarted.
// Any fresh damage bumps enr_gen, which invalidates the pending check - that
// is how re-engagement cancels a reset with no timestamp arithmetic.
//
// The reset is deliberately IN PLACE rather than "destroy and re-create from
// the blueprint". A CreateObject copy of one of the spawn_type='encounter'
// registry bosses is no longer an encounter creature, so its death would arm
// se_respawn_inc's own respawn *and* leave the lair encounter free to spawn
// its own - the two-live-bosses case the design explicitly rules out.
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
//   int    enr_respawn    cached boss_registry.respawn_seconds (reset delay)
//   int    enr_n          number of engaged entries
//   object enr_pc_<i>     engaged PC
//   string enr_name_<i>   PC first name, captured at engage (survives logout)
//   int    enr_out_<i>    consecutive out-of-range strikes
//   int    enr_ticking    guard: the pseudo-heartbeat loop is scheduled
//   int    enr_stacks     enrage stacks applied this life (debug/telemetry)
//   int    enr_gen        engagement generation; bumped on every damage, so a
//                         pending reset check knows it is stale
//   int    enr_snap       1 once the item snapshot has been taken this life
//   int    enr_it_n       snapshot entry count
//   string enr_it_<i>     snapshot resref
//   int    enr_islot_<i>  snapshot equip slot, -1 = carried in the backpack
//   int    enr_iqty_<i>   snapshot stack size

#include "brd_db"

const float  ENR_RANGE      = 40.0;  // metres; past this (or out of area) = retreating
const float  ENR_TICK       = 6.0;   // seconds between disengage scans
const int    ENR_STRIKES    = 2;     // consecutive out-of-range ticks = disengaged
const string ENR_EFFECT_TAG = "enr_rage";  // so the reset can strip exactly these
const int    ENR_MAX_SNAP   = 40;    // snapshot cap (no boss carries near this)
const float  ENR_RECHECK    = 60.0;  // re-arm delay when still in combat at reset time

// TRUE when oCre is on the Roll-of-the-Fallen boss registry. One campaign-DB
// lookup per creature life, cached in a local - which also caches the boss's
// own respawn_seconds, the delay the out-of-combat reset waits out.
int ENR_IsRegistryBoss(object oCre)
{
    int nCache = GetLocalInt(oCre, "enr_isboss");
    if (nCache != 0) return (nCache == 1);

    string sRef = BRD_Canonical(GetResRef(oCre));
    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT respawn_seconds FROM boss_registry WHERE resref=@r");
    SqlBindString(q, "@r", sRef);
    int bBoss = SqlStep(q);
    if (bBoss) SetLocalInt(oCre, "enr_respawn", SqlGetInt(q, 0));

    SetLocalInt(oCre, "enr_isboss", bBoss ? 1 : -1);
    return bBoss;
}

// How long this boss must stay out of combat before it resets: its own
// registry respawn time, so the wait matches what killing it would have cost.
float ENR_ResetDelay(object oBoss)
{
    int nSec = GetLocalInt(oBoss, "enr_respawn");
    if (nSec <= 0) nSec = 900;       // registry default, and a safe fallback
    return IntToFloat(nSec);
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
    // Tagged so ENR_DoReset can strip exactly these and nothing else.
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(TagEffect(eBuff, ENR_EFFECT_TAG)), oBoss);

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

// ------------------------------------------------------------
// Out-of-combat reset (the enrage "decay")

// Snapshot the boss's kit the first time it is damaged in a life, before
// anyone can loot or pickpocket it. Equip slots 0-13 only: 14-17 are creature
// weapons/hide, which cannot be taken.
void ENR_Snapshot(object oBoss)
{
    if (GetLocalInt(oBoss, "enr_snap")) return;
    SetLocalInt(oBoss, "enr_snap", 1);

    int n = 0;
    int nSlot;
    object oItem;

    for (nSlot = 0; nSlot < INVENTORY_SLOT_CWEAPON_L; nSlot++)
    {
        oItem = GetItemInSlot(nSlot, oBoss);
        if (!GetIsObjectValid(oItem)) continue;
        SetLocalString(oBoss, "enr_it_"    + IntToString(n), GetResRef(oItem));
        SetLocalInt   (oBoss, "enr_islot_" + IntToString(n), nSlot);
        SetLocalInt   (oBoss, "enr_iqty_"  + IntToString(n), GetItemStackSize(oItem));
        n++;
    }

    oItem = GetFirstItemInInventory(oBoss);
    while (GetIsObjectValid(oItem) && n < ENR_MAX_SNAP)
    {
        SetLocalString(oBoss, "enr_it_"    + IntToString(n), GetResRef(oItem));
        SetLocalInt   (oBoss, "enr_islot_" + IntToString(n), -1);
        SetLocalInt   (oBoss, "enr_iqty_"  + IntToString(n), GetItemStackSize(oItem));
        n++;
        oItem = GetNextItemInInventory(oBoss);
    }

    SetLocalInt(oBoss, "enr_it_n", n);
}

// How many of sResRef the boss holds right now, counting stack sizes.
int ENR_CountItem(object oBoss, string sResRef)
{
    int nHave = 0;
    int nSlot;
    object oItem;

    for (nSlot = 0; nSlot < INVENTORY_SLOT_CWEAPON_L; nSlot++)
    {
        oItem = GetItemInSlot(nSlot, oBoss);
        if (GetIsObjectValid(oItem) && GetResRef(oItem) == sResRef)
            nHave += GetItemStackSize(oItem);
    }

    oItem = GetFirstItemInInventory(oBoss);
    while (GetIsObjectValid(oItem))
    {
        if (GetResRef(oItem) == sResRef) nHave += GetItemStackSize(oItem);
        oItem = GetNextItemInInventory(oBoss);
    }
    return nHave;
}

// First carried item with this resref (GetItemPossessedBy matches on TAG, not
// resref, so it is no use here).
object ENR_FindItem(object oBoss, string sResRef)
{
    object oItem = GetFirstItemInInventory(oBoss);
    while (GetIsObjectValid(oItem))
    {
        if (GetResRef(oItem) == sResRef) return oItem;
        oItem = GetNextItemInInventory(oBoss);
    }
    return OBJECT_INVALID;
}

// Put back whatever went missing since the snapshot - looted, pickpocketed or
// drunk. A TOP-UP, never a wipe: anything the boss has gained meanwhile is
// left alone (same rule as kalrist_gems.nss).
void ENR_RestoreItems(object oBoss)
{
    int nN = GetLocalInt(oBoss, "enr_it_n");
    int i;
    int j;

    for (i = 0; i < nN; i++)
    {
        string sRef = GetLocalString(oBoss, "enr_it_" + IntToString(i));
        if (sRef == "") continue;

        // Aggregate by resref: skip if an earlier entry already handled it.
        int bDone = FALSE;
        for (j = 0; j < i; j++)
        {
            if (GetLocalString(oBoss, "enr_it_" + IntToString(j)) == sRef)
            {
                bDone = TRUE;
                break;
            }
        }
        if (bDone) continue;

        int nWant = 0;
        for (j = i; j < nN; j++)
        {
            if (GetLocalString(oBoss, "enr_it_" + IntToString(j)) == sRef)
                nWant += GetLocalInt(oBoss, "enr_iqty_" + IntToString(j));
        }

        // ONE CreateItemOnObject per item. Its stack argument is clamped to the
        // base item's baseitems.2da Stacking value, so asking for six of a
        // non-stackable item silently yields one - see CLAUDE-gotchas.md,
        // "Handing out N of an item". Stackable items merge on their own.
        int nMissing = nWant - ENR_CountItem(oBoss, sRef);
        while (nMissing > 0)
        {
            CreateItemOnObject(sRef, oBoss);
            nMissing--;
        }
    }

    // Re-equip anything that was worn when the fight started and is not now.
    for (i = 0; i < nN; i++)
    {
        int nSlot = GetLocalInt(oBoss, "enr_islot_" + IntToString(i));
        if (nSlot < 0) continue;
        if (GetIsObjectValid(GetItemInSlot(nSlot, oBoss))) continue;

        object oItem = ENR_FindItem(oBoss,
            GetLocalString(oBoss, "enr_it_" + IntToString(i)));
        if (GetIsObjectValid(oItem))
            AssignCommand(oBoss, ActionEquipItem(oItem, nSlot));
    }
}

// Strip every enrage stack (and nothing else - the stacks are the only tagged
// effects this system applies).
void ENR_ClearEnrage(object oBoss)
{
    effect e = GetFirstEffect(oBoss);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == ENR_EFFECT_TAG) RemoveEffect(oBoss, e);
        e = GetNextEffect(oBoss);
    }
    DeleteLocalInt(oBoss, "enr_stacks");
}

// Full restore, in place. See the header for why this is not a re-create.
void ENR_DoReset(object oBoss)
{
    if (!GetIsObjectValid(oBoss) || GetIsDead(oBoss)) return;

    ENR_ClearEnrage(oBoss);

    // Spells and feats per day back, plus hit points; the explicit heal is
    // belt-and-braces in case a boss is holding damage ForceRest does not clear.
    ForceRest(oBoss);
    int nMissing = GetMaxHitPoints(oBoss) - GetCurrentHitPoints(oBoss);
    if (nMissing > 0)
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(nMissing), oBoss);

    ENR_RestoreItems(oBoss);

    // Home: the same "spawn" location leash_to_area sends a kited boss back to.
    location lHome = GetLocalLocation(oBoss, "spawn");
    if (GetIsObjectValid(GetAreaFromLocation(lHome)))
    {
        AssignCommand(oBoss, ClearAllActions());
        AssignCommand(oBoss, JumpToLocation(lHome));
    }

    // A clean slate: the next damage re-snapshots and re-arms everything.
    SetLocalInt(oBoss, "enr_n", 0);
    DeleteLocalInt(oBoss, "enr_snap");
    SetLocalInt(oBoss, "enr_gen", GetLocalInt(oBoss, "enr_gen") + 1);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_HEALING_X), oBoss);
    AssignCommand(oBoss, SpeakString(
        "My wounds close and my strength returns. Begin again, if you dare.",
        TALKVOLUME_SHOUT));
}

// Armed by ENR_Tick once nobody is engaged, for ENR_ResetDelay seconds.
// nGen is the engagement generation at arming time: any damage in between
// bumps enr_gen and makes this check a no-op.
void ENR_ResetCheck(object oBoss, int nGen)
{
    if (!GetIsObjectValid(oBoss) || GetIsDead(oBoss)) return;
    if (GetLocalInt(oBoss, "enr_gen") != nGen) return;   // re-engaged since
    if (GetLocalInt(oBoss, "enr_n") > 0)      return;    // someone is engaged

    // Still swinging at something - a boss chasing a PC who has stopped
    // hitting back. Wait for the fight to actually end.
    if (GetIsInCombat(oBoss))
    {
        DelayCommand(ENR_RECHECK, ENR_ResetCheck(oBoss, nGen));
        return;
    }

    ENR_DoReset(oBoss);
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
    {
        DelayCommand(ENR_TICK, ENR_Tick(oBoss));
        return;
    }

    SetLocalInt(oBoss, "enr_ticking", 0);

    // Nobody left in the fight: arm the out-of-combat reset for this boss's own
    // respawn duration. Only for a boss that has actually been damaged this
    // life (enr_snap is set by the first damage), and only until the next
    // damage bumps enr_gen out from under it.
    if (GetLocalInt(oBoss, "enr_snap"))
        DelayCommand(ENR_ResetDelay(oBoss),
            ENR_ResetCheck(oBoss, GetLocalInt(oBoss, "enr_gen")));
}

// Entry point, called from bst_ondamage with the master-chain-resolved owning
// PC. OBJECT_SELF is the damaged creature. No-ops for anything that isn't a
// registry boss.
void ENR_OnBossDamaged(object oCre, object oPC)
{
    if (!GetIsObjectValid(oCre) || GetIsDead(oCre)) return;
    if (!GetIsObjectValid(oPC)) return;
    if (!ENR_IsRegistryBoss(oCre)) return;

    // Fresh damage: a new engagement generation, so any pending out-of-combat
    // reset check knows it is stale. The kit snapshot is taken here too, once
    // per life, before anyone can loot or pickpocket the boss.
    SetLocalInt(oCre, "enr_gen", GetLocalInt(oCre, "enr_gen") + 1);
    ENR_Snapshot(oCre);

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
