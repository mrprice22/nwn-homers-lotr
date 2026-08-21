// fat_inc - soul-fatigue on the full-heal spells and Heal potions
// (roadmap: heal-soul-fatigue, heal-soul-fatigue-rebalance).
//
// Design spec: docs.manual/boss-updates.html#fatigue.
//
// Turns reflexive full-heal spam into a timed resource. When a living PC is
// healed by one of the three full-HP-restore spells - Heal (including
// potion/item activations, they fire the same spell id through the module
// override spellscript), Mass Heal, or Greater Restoration - three things
// happen in strict order:
//   1. the heal fully resolves first (we only schedule work AFTER the real
//      impact script has run),
//   2. the PC then takes 8% of max HP as damage PER stack that was already
//      active BEFORE this heal - applied after the top-off so the heal can't
//      erase it. This can kill: at 13 prior stacks the hit exceeds 100% of
//      max HP. The hit is a raw hit-point drain, not damage, and it is written
//      through both the script and the NWNX hit-point layers so that neither
//      resistances nor a polymorph form's separate HP pool can swallow it -
//      see FAT_DrainHP.
//   3. a new stack is added.
// Each stack decays on its own independent 3-minute timer. A heal from zero
// stacks is therefore completely free: full heal, 1 stack, no damage.
//
// Persistence - stacks are a PERSONAL DEBT, and there is no way to dodge it:
//   * They survive a relog. The queue is stored per character in the
//     "fatiguedb" campaign DB, keyed on GetObjectUUID (same convention as the
//     bestiary and the pipeweed high), rewritten on every add and every
//     expiry, and restored at login.
//   * Decay PAUSES while the character is offline. Each stack carries its
//     REMAINING seconds, not a wall-clock expiry, and those seconds are only
//     spent by the per-PC ticker below - which only runs while the PC is in
//     the world. Logging out to wait the timer down does nothing.
//   * Death does not clear them either. Nothing in this file (or anywhere
//     else) resets the queue on death or respawn; dying with a full stack
//     count means coming back with it.
//   * A SERVER REBOOT does clear them, for everyone - FAT_WipeAll() from
//     onmoduleload.nss. No combat survived the restart: every boss and creature
//     that caused the stacks is reset at load, so the debt resets with them.
//     This is the one and only way out of the queue besides waiting it down.
// The old implementation used one independent DelayCommand per stack and a
// plain local int. That decayed in real time whether or not you were logged
// in, and a relog wiped the lot - both are now closed.
//
// Mitigation - the Heal SKILL (this is its end-game utility): the CASTER's
// total Heal skill (ranks + Wisdom + item bonuses, i.e. GetSkillRank, not base
// ranks) reduces the fatigue damage by 0.5% per point, counting up to 60
// points, for a maximum 30% reduction. For a potion or a self-cast the caster
// is the drinker, so a healer's own investment protects them too. With the cap
// reached the effective cost is 5.6% per stack and the lethal point moves out
// to 18 prior stacks (the 19th chained heal inside one 3-minute window).
//
// Hook: stop_spellcheat.nss (the SetModuleOverrideSpellscript script installed
// by onmoduleload.nss, the real Mod_OnModLoad) calls FAT_OnOverrideSpellCast()
// on every cast (via x2_inc_spellhook's X2RunUserDefinedSpellScript). The
// override script runs at spell impact, immediately BEFORE the spell's own
// impact script; our DelayCommand therefore lands after the heal has resolved.
//
// Scope / defensive rules:
//   * PCs only, never DMs. NPCs healing themselves are unaffected.
//   * An undead target isn't being healed by these spells (they harm it) -
//     no stack, no damage.
//   * Mass Heal mirrors the module impact script nw_s0_masheal.nss exactly:
//     friendly, non-undead targets in a MEDIUM sphere at the target location
//     (that script staggers its heals by a random <=~1.1 s delay per target,
//     so the fatigue hit waits FAT_LAND_MASS seconds).
//   * The damage/stack work is assigned to the module object so it survives
//     the caster dying/logging out; every callback re-validates its PC first.
//     The DECAY ticker is deliberately the opposite - see FAT_Kick().
//
// Locals used (on the PC):
//   int    fat_stacks   currently active soul-fatigue stacks (= entries in the
//                       queue below; kept as an int so the damage maths and
//                       any future reader don't have to parse the string)
//   string fat_queue    the queue itself: one comma-terminated integer per
//                       stack, its REMAINING seconds, e.g. "180,174,12,"
//   int    fat_ticking  the ticker's kill switch / double-start guard

#include "nwnx_object"   // SetCurrentHitPoints fallback, see FAT_DrainHP

const string FAT_VAR        = "fat_stacks";
const string FAT_QVAR       = "fat_queue";
const string FAT_RUNVAR     = "fat_ticking";
const string FAT_DB         = "fatiguedb";
const string FAT_TICK_SCRIPT = "fat_tick";
const int    FAT_PCT        = 8;      // % of max HP damage per prior stack
const int    FAT_DECAY_SEC  = 180;    // seconds a stack lasts (3 minutes)
const int    FAT_TICK_SEC   = 6;      // ticker granularity, seconds
const float  FAT_TICK       = 6.0;    // ... the same, as a delay
const float  FAT_LAND       = 1.0;    // Heal: delay so the heal resolves first
const float  FAT_LAND_MASS  = 2.0;    // Mass Heal: outlasts its staggered heals
const int    FAT_SKILL_PER  = 5;      // damage reduction per Heal point, in
                                      // TENTHS of a percent (5 => 0.5%/point)
const int    FAT_SKILL_CAP  = 60;     // Heal points counted (=> 30% max off)

// --- persistence ------------------------------------------------------------

// Idempotent. Called from onmoduleload.nss and again from mod_cliententer.nss,
// so the table exists even if load ordering never reached the first call.
void FAT_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(FAT_DB,
        "CREATE TABLE IF NOT EXISTS fatigue ("
        + "uuid TEXT PRIMARY KEY,"
        + "stacks INTEGER NOT NULL DEFAULT 0,"
        + "queue TEXT NOT NULL DEFAULT '',"
        + "cdkey TEXT, char_name TEXT, updated_at TEXT)");
    SqlStep(q);
}

// Write the live queue back. Called on every change (not just at logout) so a
// server crash can't be used to shed stacks either.
void FAT_Save(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nStacks = GetLocalInt(oPC, FAT_VAR);
    if (nStacks <= 0)
    {
        // Clean the row out rather than storing an empty queue: a character
        // with no stacks has nothing to restore, and the table stays small.
        sqlquery qd = SqlPrepareQueryCampaign(FAT_DB,
            "DELETE FROM fatigue WHERE uuid=@u");
        SqlBindString(qd, "@u", GetObjectUUID(oPC));
        SqlStep(qd);
        return;
    }

    sqlquery q = SqlPrepareQueryCampaign(FAT_DB,
        "INSERT INTO fatigue(uuid,stacks,queue,cdkey,char_name,updated_at)"
        + " VALUES(@u,@s,@q,@k,@n,datetime('now'))"
        + " ON CONFLICT(uuid) DO UPDATE SET"
        + " stacks=excluded.stacks,"
        + " queue=excluded.queue,"
        + " cdkey=excluded.cdkey,"
        + " char_name=excluded.char_name,"
        + " updated_at=excluded.updated_at");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindInt(q,    "@s", nStacks);
    SqlBindString(q, "@q", GetLocalString(oPC, FAT_QVAR));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlStep(q);
}

// Wipe the whole table. Called from onmoduleload.nss: soul-fatigue does not
// survive a reboot, because no combat did - every boss and creature that caused
// the stacks is reset at load, so the debt resets with them.
void FAT_WipeAll()
{
    sqlquery q = SqlPrepareQueryCampaign(FAT_DB, "DELETE FROM fatigue");
    SqlStep(q);
}

// Drop every fatigue local from a PC.
//
// This exists because of the player TURD: when a player disconnects, the server
// keeps a serialised copy of the PC object - LOCAL VARIABLES INCLUDED - for the
// rest of the server session, and restores it when the same player reconnects.
// The delayed-command chain that was doing the ticking died with the old object,
// but fat_ticking comes back TRUE, and FAT_Kick's "already ticking" guard then
// blocks the ticker FOREVER: no login restore and no later heal can ever re-arm
// it. That is the relog bug - stacks frozen for the life of the character.
// So the guard (and the counters, which the DB is authoritative for) is cleared
// on the way in, before anything can read it.
void FAT_ClearLocals(object oPC)
{
    if (!GetIsObjectValid(oPC)) return;
    DeleteLocalInt(oPC, FAT_VAR);
    DeleteLocalString(oPC, FAT_QVAR);
    DeleteLocalInt(oPC, FAT_RUNVAR);
}

// Clear just the ticker guard, for the logout path - so the TURD is never even
// written with a guard that has no ticker behind it.
void FAT_ClearTickGuard(object oPC)
{
    if (!GetIsObjectValid(oPC)) return;
    DeleteLocalInt(oPC, FAT_RUNVAR);
}

// --- the decay ticker -------------------------------------------------------

// Start (or restart) the per-PC ticker if it isn't already running.
//
// Note what this deliberately does NOT do: it does not assign the delay to the
// module. The DelayCommand rides on the PC, so it simply stops firing when the
// character leaves the world and is re-armed by FAT_LoginRestore on the way
// back in. That IS the "decay pauses while logged out" rule - remaining
// seconds are only ever spent by a tick that actually ran.
void FAT_Kick(object oPC)
{
    if (GetLocalInt(oPC, FAT_RUNVAR)) return;          // already ticking
    if (GetLocalInt(oPC, FAT_VAR) <= 0) return;        // nothing to decay
    SetLocalInt(oPC, FAT_RUNVAR, TRUE);
    AssignCommand(oPC,
        DelayCommand(FAT_TICK, ExecuteScript(FAT_TICK_SCRIPT, oPC)));
}

// How many stacks a queue string holds - one comma-terminated entry each.
// Same scan shape as FAT_AgeQueue below; used to keep fat_stacks in step when
// two queues are merged at login.
int FAT_CountQueue(string sQ)
{
    int nCount = 0;
    int p = FindSubString(sQ, ",");
    while (p >= 0)
    {
        nCount++;
        sQ = GetSubString(sQ, p + 1, GetStringLength(sQ) - p - 1);
        p = FindSubString(sQ, ",");
    }
    return nCount;
}

// Age every stack by nSecs and drop the ones that ran out. Returns how many
// fell off. Rebuilds fat_queue and keeps fat_stacks in step with it.
int FAT_AgeQueue(object oPC, int nSecs)
{
    string sQ = GetLocalString(oPC, FAT_QVAR);
    string sOut = "";
    int nGone = 0, nKept = 0;

    int p = FindSubString(sQ, ",");
    while (p >= 0)
    {
        int nRem = StringToInt(GetSubString(sQ, 0, p)) - nSecs;
        sQ = GetSubString(sQ, p + 1, GetStringLength(sQ) - p - 1);
        if (nRem > 0)
        {
            sOut += IntToString(nRem) + ",";
            nKept++;
        }
        else nGone++;
        p = FindSubString(sQ, ",");
    }

    SetLocalString(oPC, FAT_QVAR, sOut);
    SetLocalInt(oPC, FAT_VAR, nKept);
    return nGone;
}

// One tick. Called from fat_tick.nss with OBJECT_SELF = the PC.
void FAT_Tick(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return;
    if (!GetLocalInt(oPC, FAT_RUNVAR)) return;         // kill switch

    int nGone = FAT_AgeQueue(oPC, FAT_TICK_SEC);
    int nLeft = GetLocalInt(oPC, FAT_VAR);

    if (nGone > 0)
    {
        FAT_Save(oPC);
        if (nLeft > 0)
            FloatingTextStringOnCreature("A stack of soul-fatigue fades ("
                + IntToString(nLeft) + " remaining).", oPC, FALSE);
        else
            FloatingTextStringOnCreature(
                "The soul-fatigue lifts. The next heal is free.", oPC, FALSE);
    }

    if (nLeft > 0)
        DelayCommand(FAT_TICK, ExecuteScript(FAT_TICK_SCRIPT, oPC));
    else
        DeleteLocalInt(oPC, FAT_RUNVAR);
}

// Login: pull the stored queue back onto the PC and re-arm the ticker, so the
// clock restarts exactly where it stopped. Called from mod_cliententer.nss,
// delayed past the login flood and past the GetObjectUUID forcing call there.
//
// The campaign DB is AUTHORITATIVE here, never the locals on the object: after
// a reconnect those may be whatever the player TURD carried over (see
// FAT_ClearLocals), and after a reboot wipe they would resurrect stacks that no
// longer exist. The one thing worth keeping off the object is a stack earned
// since this character entered - a heal can land inside the login window, ahead
// of this call - so that queue is merged in rather than overwritten.
void FAT_LoginRestore(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC) || GetIsDM(oPC)) return;

    string sInterim = GetLocalString(oPC, FAT_QVAR);

    // Never leave a guard with no ticker behind it - this is the relog fix.
    DeleteLocalInt(oPC, FAT_RUNVAR);

    string sStored = "";
    sqlquery q = SqlPrepareQueryCampaign(FAT_DB,
        "SELECT stacks,queue FROM fatigue WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (SqlStep(q) && SqlGetInt(q, 0) > 0) sStored = SqlGetString(q, 1);

    string sQueue = sStored + sInterim;
    int nStacks = FAT_CountQueue(sQueue);

    SetLocalString(oPC, FAT_QVAR, sQueue);
    SetLocalInt(oPC, FAT_VAR, nStacks);

    if (nStacks <= 0)
    {
        // Nothing stored and nothing earned since entering. Clear the locals out
        // rather than leaving an empty queue behind, and say nothing.
        FAT_ClearLocals(oPC);
        return;
    }

    // Keep the row in step with the merge (and re-create it if a stack was
    // earned in the login window with no row stored).
    FAT_Save(oPC);
    FAT_Kick(oPC);

    int nRestored = FAT_CountQueue(sStored);
    if (nRestored > 0)
        FloatingTextStringOnCreature("You return still soul-weary: "
            + IntToString(nRestored) + " stack" + (nRestored == 1 ? "" : "s")
            + " of soul-fatigue. It does not fade while you are away.",
            oPC, FALSE);
}

// --- the hit ----------------------------------------------------------------

// Take nDmg hit points off oPC as a scripted cost - not as damage.
//
// Why not EffectDamage: EVERY damage type, DAMAGE_TYPE_MAGICAL included, can be
// soaked by damage resistance, immunity % or DR, and geared PCs reduced the old
// magical hit to zero. A soul-fatigue hit is a bill, not an attack.
//
// Why not the plain SetCurrentHitPoints write either (roadmap:
// soul-fatigue-not-working-while-shapeshifted): while a PC is POLYMORPHED the
// engine keeps a second hit-point pool for the form, and a script-layer write
// does not reliably land on the pool the player is actually standing on - the
// module already works around the same split in pers_state_inc.nss (HP capture
// is skipped for morphed shifters because "their morphed HP would stomp the
// real value") and in pc_export_inc.nss. Players in dragon shape could chain
// Heal potions and never lose a point.
//
// So the drain is written through BOTH layers and then verified. Both writes
// are ABSOLUTE (set to nTarget, never subtract), so doing both unconditionally
// is idempotent - it can never double-charge - and whichever layer is
// authoritative for the shape the PC is in, one of them lands. Only if HP still
// has not moved do we fall back to EffectDamage, soakable but better than the
// free heal it replaces.
//
// Returns the HP actually removed (0 if even the fallback was fully soaked).
int FAT_DrainHP(object oPC, int nTarget)
{
    int nBefore = GetCurrentHitPoints(oPC);
    if (nTarget < 1) nTarget = 1;
    if (nTarget >= nBefore) return 0;

    SetCurrentHitPoints(oPC, nTarget);
    NWNX_Object_SetCurrentHitPoints(oPC, nTarget);

    int nAfter = GetCurrentHitPoints(oPC);
    if (nAfter > nTarget)
    {
        // Neither write took on this creature. Pay what we can.
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectDamage(nBefore - nTarget, DAMAGE_TYPE_MAGICAL,
                         DAMAGE_POWER_ENERGY), oPC);
        nAfter = GetCurrentHitPoints(oPC);
    }

    if (nAfter > nBefore) return 0;
    return nBefore - nAfter;
}

// The ordered mechanic. Runs AFTER the heal has landed on oPC:
// damage for the stacks held before this heal, then add the new stack.
// nHeal is the CASTER's total Heal skill, captured at cast time (so it still
// applies if the caster dies or logs out before this lands).
void FAT_ApplyToPC(object oPC, int nHeal)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (GetIsDead(oPC)) return;   // died between cast and impact: no stack

    // Clamp the skill: GetSkillRank returns -1 for an untrained non-class
    // skill, and only the first FAT_SKILL_CAP points count.
    if (nHeal < 0) nHeal = 0;
    if (nHeal > FAT_SKILL_CAP) nHeal = FAT_SKILL_CAP;
    int nCut = nHeal * FAT_SKILL_PER;   // reduction in tenths of a percent

    int nPrior = GetLocalInt(oPC, FAT_VAR);

    if (nPrior > 0)
    {
        // The percentage basis. GetMaxHitPoints reports the character sheet,
        // which a polymorph form's own hit-point pool can exceed - take
        // whichever is larger so a shape can never shrink the bill (and so a
        // 0 returned on error cannot silently zero the whole hit).
        int nCur = GetCurrentHitPoints(oPC);
        int nMax = GetMaxHitPoints(oPC);
        if (nCur > nMax) nMax = nCur;

        // Integer maths in thousandths so 0.5%/point is exact - no floats.
        int nDmg = nMax * FAT_PCT * nPrior / 100;
        nDmg = nDmg * (1000 - nCut) / 1000;
        if (nDmg < 1) nDmg = 1;   // a carried stack always costs something
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_NEGATIVE_ENERGY), oPC);

        int nNew = nCur - nDmg;
        if (nNew < 1)
        {
            // Lethal. Base-game SetCurrentHitPoints floors at 1 and never
            // kills, so force death explicitly. (A PC with outright death
            // immunity would survive at 1 HP - a rare, accepted corner.)
            FAT_DrainHP(oPC, 1);
            ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectDeath(FALSE, FALSE), oPC);
        }
        else
        {
            nDmg = FAT_DrainHP(oPC, nNew);
            if (nDmg < 1) nDmg = nCur - nNew;   // report the bill, not 0
        }
        string sCut = "";
        if (nCut > 0)
            sCut = ", -" + IntToString(nCut / 10)
                 + (nCut % 10 != 0 ? ".5" : "")
                 + "% from the healer's Heal skill";

        FloatingTextStringOnCreature("Soul-fatigue tears at you for "
            + IntToString(nDmg) + " damage ("
            + IntToString(nPrior) + " stack" + (nPrior == 1 ? "" : "s")
            + " x " + IntToString(FAT_PCT) + "% of max HP"
            + sCut + ").", oPC, FALSE);
    }

    // The new stack - even if the fatigue damage just killed them. Death does
    // not clear the queue; the debt is carried through the respawn.
    int nNow = GetLocalInt(oPC, FAT_VAR) + 1;
    SetLocalInt(oPC, FAT_VAR, nNow);
    SetLocalString(oPC, FAT_QVAR, GetLocalString(oPC, FAT_QVAR)
        + IntToString(FAT_DECAY_SEC) + ",");
    FAT_Save(oPC);
    FAT_Kick(oPC);

    FloatingTextStringOnCreature("Soul-fatigue: " + IntToString(nNow)
        + " stack" + (nNow == 1 ? "" : "s")
        + ". Another heal within 3 minutes will cost up to "
        + IntToString(nNow * FAT_PCT)
        + "% of your max HP after it lands (less the healer's Heal skill).",
        oPC, FALSE);
}

// Entry point, called from stop_spellcheat.nss with OBJECT_SELF = the caster
// (for potions/items: the user). Runs on EVERY cast - bail out fast.
void FAT_OnOverrideSpellCast()
{
    int nSpell = GetSpellId();
    if (nSpell != SPELL_HEAL && nSpell != SPELL_MASS_HEAL
        && nSpell != SPELL_GREATER_RESTORATION) return;

    // The caster's (or potion/item user's) total Heal skill - read once, here,
    // so it survives the caster dying or logging out before impact.
    int nHeal = GetSkillRank(SKILL_HEAL, OBJECT_SELF);
    if (nHeal < 0) nHeal = 0;

    // Heal and Greater Restoration are both single-target full restores.
    if (nSpell == SPELL_HEAL || nSpell == SPELL_GREATER_RESTORATION)
    {
        object oTarget = GetSpellTargetObject();
        if (!GetIsObjectValid(oTarget)) return;
        if (!GetIsPC(oTarget) || GetIsDM(oTarget)) return;
        // Heal cast at undead is an attack, not a heal - no fatigue.
        if (GetRacialType(oTarget) == RACIAL_TYPE_UNDEAD) return;
        AssignCommand(GetModule(),
            DelayCommand(FAT_LAND, FAT_ApplyToPC(oTarget, nHeal)));
        return;
    }

    // Mass Heal: mirror nw_s0_masheal targeting (friendly, non-undead,
    // MEDIUM sphere at the target location).
    location lLoc = GetSpellTargetLocation();
    object oT = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_MEDIUM, lLoc);
    while (GetIsObjectValid(oT))
    {
        if (GetIsPC(oT) && !GetIsDM(oT)
            && GetRacialType(oT) != RACIAL_TYPE_UNDEAD
            && GetIsFriend(oT))
        {
            AssignCommand(GetModule(),
                DelayCommand(FAT_LAND_MASS, FAT_ApplyToPC(oT, nHeal)));
        }
        oT = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_MEDIUM, lLoc);
    }
}
