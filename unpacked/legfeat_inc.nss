// legfeat_inc.nss - Legendary Feats: allotment, granting, revoking, effects.
//
// Legendary feats are inert tokens: the feat.2da row carries a name, a
// description and an icon, and nothing else. Everything a legendary feat
// actually DOES is applied here, server-side. See CLAUDE-legendary-feats.md.
//
// ALLOTMENT (at character level 60, IN ADDITION TO the normal level-60 feat the
// engine grants through its own level-up UI):
//
//     mixed class   1 pick
//     pure class    2 picks
//     pure Fighter  3 picks
//
// Fighter gets three because bonus feats are its whole identity and it has no
// magic fallback.
//
// THE ALLOTMENT IS RECOMPUTED, NOT REMEMBERED. The first version wrote the DB
// row once at level 60 and never looked again, so a pure barbarian who took 2
// picks and then relevelled to 59 barbarian / 1 bard kept both. With the level
// setter on this server that is a two-minute exploit. LegFeat_EnsureAllotment
// now re-derives the entitlement on every call - level up, level down, login.
//
// TWO THINGS REVOKE EVERY PICK:
//
//   1. The class composition changed (pure <-> multiclass, or any reshuffle).
//   2. The character is no longer level 60 - death XP loss can take a 60 back
//      to 59, and a legendary feat must not survive that. The picks are
//      re-earned on the way back up.
//
// ENERGY DRAIN IS NOT A LEVEL LOSS, and getting that wrong would be a serious
// bug - late content drains routinely, and these feats are permanent. Two
// independent guards:
//
//   * The level is judged from CLASS levels (LegFeat_TrueLevel), which live in
//     the character's class list. A negative level is an effect and removes no
//     class level.
//   * Belt and braces: if the character carries any EFFECT_TYPE_NEGATIVELEVEL,
//     no revoke decision is made at all. The check re-runs at the next login or
//     level event, so deferring costs nothing.
//
// EFFECTS: TWO KINDS, AND THE DIFFERENCE MATTERS
//
//   LEGFEAT_KIND_RAW    - writes the character's BASE ability score
//                         (NWNX_Creature_SetRawAbilityScore, the same route
//                         Akira's Mixtape uses in mw_mixtape_con.nss). Saved in
//                         the .bic. Applied exactly ONCE, at the moment of the
//                         pick, and NEVER re-applied at login: doing so would
//                         stack another +6 into the character every session,
//                         silently and permanently.
//   LEGFEAT_KIND_EFFECT - a permanent supernatural effect, tagged
//                         LEGFEAT_EFFECT_TAG and rebuilt on every login by
//                         LegFeat_ApplyAll. Legendary Assault and Legendary
//                         Onslaught are the first two.
//
// Ability bonuses were LEGFEAT_KIND_EFFECT in the first build. UAT found the
// problem: an EffectAbilityIncrease renders as a *buffed* score (green, with a
// buff icon) and counts against the server's maximum enchantment ability bonus,
// so a character already at the gear cap gained nothing at all from the feat.
// A base-score write is what the design actually needed.

#include "legfeat_ids_inc"
#include "legfeat_db"
#include "nwnx_creature"

const int    LEGFEAT_LEVEL      = 60;              // picks unlock at exactly 60
const string LEGFEAT_EFFECT_TAG = "LEGFEAT_EFF";   // every EFFECT-kind effect
const int    LEGFEAT_MIN_STAT   = 3;               // floor when undoing a bonus

int    LegFeat_TrueLevel(object oPC);
int    LegFeat_HasNegativeLevels(object oPC);
int    LegFeat_IsPolymorphed(object oPC);
string LegFeat_ClassSig(object oPC);
int    LegFeat_Allotment(object oPC);
int    LegFeat_Remaining(object oPC);
int    LegFeat_EnsureAllotment(object oPC);
int    LegFeat_IndexOf(int nFeatId);
int    LegFeat_IsMeleeArmed(object oPC);
int    LegFeat_Take(object oPC, int nIndex);
void   LegFeat_ApplyOne(object oPC, int nFeatId);
void   LegFeat_ApplyAll(object oPC);
void   LegFeat_RevokeAll(object oPC, string sReason);
int    LegFeat_ResetCharacter(object oPC);
int    LegFeat_Respec(object oPC);

// Character level from CLASS levels, which no effect can touch. Deliberately
// not GetHitDice(): whether that tracks effective level under energy drain is
// exactly the thing we must not depend on.
int LegFeat_TrueLevel(object oPC)
{
    return GetLevelByPosition(1, oPC) + GetLevelByPosition(2, oPC)
         + GetLevelByPosition(3, oPC) + GetLevelByPosition(4, oPC);
}

int LegFeat_HasNegativeLevels(object oPC)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_NEGATIVELEVEL) return TRUE;
        e = GetNextEffect(oPC);
    }
    return FALSE;
}

// Base ability scores are swapped out while polymorphed, so a raw-score write
// made in that state is either lost or double-applied when the shape ends.
// Every path that adds or subtracts base points refuses while shifted.
int LegFeat_IsPolymorphed(object oPC)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_POLYMORPH) return TRUE;
        e = GetNextEffect(oPC);
    }
    return FALSE;
}

// Sorted class ids with any levels, e.g. "36" (pure barbarian) or "1,36"
// (barbarian/bard). Levels are excluded on purpose: 59 -> 60 must not read as a
// class change, and the signature already determines the allotment.
// Walks class ids in order rather than reading the four class positions and
// sorting them: NWScript has no arrays, and this comes out sorted by
// construction. That ordering is the point - taking the same classes in a
// different order must not read as a different build.
const int LEGFEAT_MAX_CLASS_ID = 99;   // covers stock + CEP classes.2da

string LegFeat_ClassSig(object oPC)
{
    string sSig = "";
    int nId;
    for (nId = 0; nId <= LEGFEAT_MAX_CLASS_ID; nId++)
    {
        if (GetLevelByClass(nId, oPC) <= 0) continue;
        if (sSig != "") sSig += ",";
        sSig += IntToString(nId);
    }
    return sSig;
}

// How many picks this character's class spread is worth.
int LegFeat_Allotment(object oPC)
{
    // Mixed class: anything in a second, third or fourth class slot.
    if (GetLevelByPosition(2, oPC) > 0 || GetLevelByPosition(3, oPC) > 0
        || GetLevelByPosition(4, oPC) > 0)
        return 1;

    if (GetClassByPosition(1, oPC) == CLASS_TYPE_FIGHTER) return 3;
    return 2;
}

// Picks granted but not yet spent.
int LegFeat_Remaining(object oPC)
{
    int n = LegFeat_GetGranted(oPC) - LegFeat_GetSpent(oPC);
    return (n > 0) ? n : 0;
}

// Picker index (0..LEGFEAT_COUNT-1) for a feat id, or -1 if it is not ours.
int LegFeat_IndexOf(int nFeatId)
{
    int n = nFeatId - LEGFEAT_FIRST;
    if (n < 0 || n >= LEGFEAT_COUNT) return -1;
    return n;
}

// Is this character fighting in melee right now? Unarmed counts - the only
// thing that answers FALSE is a ranged weapon in the right hand.
//
// Read by CONDITIONAL feats (Legendary Onslaught), whose effect depends on what
// is held rather than on the feat alone. Those are rebuilt by legfeat_equip.nss
// on every equip and unequip, so the answer here is never stale for long.
int LegFeat_IsMeleeArmed(object oPC)
{
    object oRight = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC);
    if (!GetIsObjectValid(oRight)) return TRUE;      // bare hands are melee
    return !GetWeaponRanged(oRight);
}

// Apply a permanent supernatural, LEGFEAT_EFF-tagged effect. Every EFFECT-kind
// feat goes through here, so the tagging that makes LegFeat_ApplyAll idempotent
// is written once and cannot be forgotten on a new feat.
void LegFeat_ApplyEffect(object oPC, effect e)
{
    e = SupernaturalEffect(e);                  // survives rest and dispel
    e = TagEffect(e, LEGFEAT_EFFECT_TAG);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, e, oPC);
}

// Apply one feat's benefit.
//
// RAW feats write the base score and are exported by the caller. EFFECT feats
// get a tagged permanent supernatural effect; idempotence for those is
// LegFeat_ApplyAll's job (it clears the tag first).
//
// ADDING A FEAT: the ability-score feats are table-driven (ability + bonus come
// from legfeat_ids_inc.nss, which the generator writes), so they need no case
// here. Everything else gets a case in the switch below. A feat with no case
// and no ability payload applies nothing at all and fails silently - the pick
// records, the feat appears on the sheet, and the benefit never arrives.
//
// The exception is LEGFEAT_KIND_HOOK, where applying nothing is the CORRECT
// behaviour: the feat is an inert token and a combat hook elsewhere reads it
// with GetHasFeat (Legendary Butcher -> unpacked/devcrit_atk.nss). Giving one a
// case here would hand out the benefit twice. LegFeat_ApplyAll skips them
// outright so they never even reach this switch.
void LegFeat_ApplyOne(object oPC, int nFeatId)
{
    int nIndex = LegFeat_IndexOf(nFeatId);
    if (nIndex < 0) return;

    int nAbility = LegFeat_AbilityAt(nIndex);
    int nBonus   = LegFeat_BonusAt(nIndex);

    if (nAbility >= 0 && nBonus > 0)
    {
        if (LegFeat_KindAt(nIndex) == LEGFEAT_KIND_RAW)
        {
            int nCur = NWNX_Creature_GetRawAbilityScore(oPC, nAbility);
            NWNX_Creature_SetRawAbilityScore(oPC, nAbility, nCur + nBonus);
            return;
        }
        LegFeat_ApplyEffect(oPC, EffectAbilityIncrease(nAbility, nBonus));
        return;
    }

    switch (nFeatId)
    {
        case FEAT_LEGENDARY_PROWESS:
            LegFeat_ApplyEffect(oPC, EffectAttackIncrease(5));
            break;

        // CONDITIONAL: melee only. EffectModifyAttacks, not an attack-speed
        // effect - it adds a whole extra attack at full BAB rather than
        // shifting the iterative progression.
        case FEAT_LEGENDARY_ONSLAUGHT:
            if (LegFeat_IsMeleeArmed(oPC))
                LegFeat_ApplyEffect(oPC, EffectModifyAttacks(1));
            break;
    }
}

// Clear and rebuild every EFFECT-kind legendary effect on this character.
//
// Call at login. RAW and HOOK feats are deliberately skipped - a RAW feat's
// bonus is already in the character's base scores and re-applying would add
// another one every session, and a HOOK feat has no effect to rebuild.
// Clearing the tag first is what makes this safe to call twice, and it
// also strips the old buff-style bonuses off characters granted feats by the
// first build.
void LegFeat_ApplyAll(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    LegFeat_InitDb();

    effect eOld = GetFirstEffect(oPC);
    while (GetIsEffectValid(eOld))
    {
        if (GetEffectTag(eOld) == LEGFEAT_EFFECT_TAG)
            RemoveEffect(oPC, eOld);
        eOld = GetNextEffect(oPC);
    }

    int i;
    for (i = 0; i < LEGFEAT_COUNT; i++)
    {
        // RAW: the bonus is already in the base scores. HOOK: the feat grants
        // nothing by design and is read by a combat hook instead. Both must be
        // left alone here.
        int nKind = LegFeat_KindAt(i);
        if (nKind == LEGFEAT_KIND_RAW || nKind == LEGFEAT_KIND_HOOK) continue;
        int nFeatId = LegFeat_IdAt(i);
        if (LegFeat_HasPick(oPC, nFeatId))
            LegFeat_ApplyOne(oPC, nFeatId);
    }
}

// Take every pick back: the feats, their base-score points, and the records.
//
// The base-score undo subtracts exactly what was granted and floors at
// LEGFEAT_MIN_STAT, so a relevel that rebuilt the character's scores underneath
// us cannot drive a stat to nonsense.
void LegFeat_RevokeAll(object oPC, string sReason)
{
    LegFeat_InitDb();
    if (LegFeat_GetSpent(oPC) <= 0)
    {
        LegFeat_ClearPicks(oPC);
        return;
    }

    int nTaken = 0;
    int i;
    for (i = 0; i < LEGFEAT_COUNT; i++)
    {
        int nFeatId = LegFeat_IdAt(i);
        if (!LegFeat_HasPick(oPC, nFeatId)) continue;
        nTaken++;

        NWNX_Creature_RemoveFeat(oPC, nFeatId);

        if (LegFeat_KindAt(i) == LEGFEAT_KIND_RAW)
        {
            int nAbility = LegFeat_AbilityAt(i);
            int nBonus   = LegFeat_BonusAt(i);
            if (nAbility >= 0 && nBonus > 0)
            {
                int nNew = NWNX_Creature_GetRawAbilityScore(oPC, nAbility) - nBonus;
                if (nNew < LEGFEAT_MIN_STAT) nNew = LEGFEAT_MIN_STAT;
                NWNX_Creature_SetRawAbilityScore(oPC, nAbility, nNew);
            }
        }
    }

    LegFeat_ClearPicks(oPC);
    LegFeat_ApplyAll(oPC);          // drops any EFFECT-kind effects too
    ExportSingleCharacter(oPC);     // write the lowered base scores through

    SendMessageToPC(oPC, "Your legendary feats have been returned to you ("
        + IntToString(nTaken) + " taken back): " + sReason);
}

// Re-derive the allotment, revoking if the character no longer qualifies for
// what it holds. Returns the number of picks now outstanding.
//
// Safe to call from anywhere and as often as you like - the allotment row is
// written with a computed value rather than incremented.
int LegFeat_EnsureAllotment(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return 0;
    LegFeat_InitDb();

    // Energy drain: make no decision at all. Whatever the right answer is, it
    // will still be the right answer at the next login or level event.
    if (LegFeat_HasNegativeLevels(oPC)) return LegFeat_Remaining(oPC);

    if (LegFeat_TrueLevel(oPC) < LEGFEAT_LEVEL)
    {
        // A real drop below 60 (death XP loss, or a relevel). Take everything
        // back and forget the allotment, so the picks are re-earned rather than
        // banked. Nothing is granted below 60, so a level setter passing
        // through the fifties grants nothing on the way.
        if (LegFeat_GetGranted(oPC) > 0 || LegFeat_GetSpent(oPC) > 0)
        {
            LegFeat_RevokeAll(oPC, "they are only held at level "
                + IntToString(LEGFEAT_LEVEL) + ".");
            LegFeat_ClearAlloc(oPC);
        }
        return 0;
    }

    string sSig    = LegFeat_ClassSig(oPC);
    string sStored = LegFeat_GetClassSig(oPC);
    int    nPicks  = LegFeat_Allotment(oPC);

    if (sStored == "")                      // first grant at 60
    {
        LegFeat_SetAlloc(oPC, nPicks, sSig);
        return LegFeat_Remaining(oPC);
    }

    if (sStored != sSig)                    // classes changed: start over
    {
        LegFeat_RevokeAll(oPC, "your class makeup changed, so they may be chosen again.");
        LegFeat_SetAlloc(oPC, nPicks, sSig);
        return nPicks;
    }

    if (LegFeat_GetGranted(oPC) != nPicks)  // same classes, different allotment
        LegFeat_SetAlloc(oPC, nPicks, sSig);

    return LegFeat_Remaining(oPC);
}

// Spend one pick on the feat at picker index nIndex.
//
// Returns TRUE if the feat was taken. Every rejection path is silent-safe: the
// caller reports, and nothing is half-applied.
int LegFeat_Take(object oPC, int nIndex)
{
    int nFeatId = LegFeat_IdAt(nIndex);
    if (nFeatId < 0) return FALSE;
    if (LegFeat_TrueLevel(oPC) < LEGFEAT_LEVEL) return FALSE;
    if (LegFeat_Remaining(oPC) <= 0) return FALSE;
    if (LegFeat_HasPick(oPC, nFeatId)) return FALSE;
    if (GetHasFeat(nFeatId, oPC)) return FALSE;   // belt and braces vs a DM grant
    if (LegFeat_IsPolymorphed(oPC)) return FALSE; // raw-score write is unsafe here

    // Prerequisites are checked HERE as well as in the picker, which greys the
    // row. The window is a client-side snapshot: it is rebuilt after each pick,
    // but a player who took the feat a prerequisite depends on, or lost one to a
    // relevel, is holding a stale list. This is the check that actually binds.
    if (!LegFeat_MeetsPrereq(oPC, nIndex)) return FALSE;

    NWNX_Creature_AddFeat(oPC, nFeatId);
    LegFeat_RecordPick(oPC, nFeatId);
    LegFeat_ApplyOne(oPC, nFeatId);

    // Base-score writes live in the .bic, so flush immediately rather than
    // trusting the character to be exported later.
    if (LegFeat_KindAt(nIndex) == LEGFEAT_KIND_RAW)
        ExportSingleCharacter(oPC);

    return TRUE;
}

// Admin test tool: put a character back to "never had a legendary feat".
//
// Returns the number of feats removed. Reached from the rest menu's Admin
// Options (legfeat_reset.nss); see README.md "Resetting a character's legendary
// feats".
//
// Two passes, because the two sources of a legendary feat need different
// treatment:
//
//   1. LegFeat_RevokeAll undoes everything we have a RECORD of granting - the
//      feat and, for base-score feats, the points.
//   2. A sweep then removes any legendary feat still on the character with no
//      record behind it: granted by a DM, or left over from a wiped legfeatdb.
//      Those have their FEAT removed but their ability score left alone, on
//      purpose - with no record that we granted the points, subtracting them
//      would be guessing, and guessing wrong permanently lowers a base stat.
//
// The allotment row goes too, so the next check grants a fresh one.
int LegFeat_ResetCharacter(object oPC)
{
    if (!GetIsPC(oPC)) return 0;
    LegFeat_InitDb();

    int nRecorded = LegFeat_GetSpent(oPC);
    if (nRecorded > 0)
        LegFeat_RevokeAll(oPC, "an administrator reset your legendary feats.");

    int nStray = 0;
    int i;
    for (i = 0; i < LEGFEAT_COUNT; i++)
    {
        int nFeatId = LegFeat_IdAt(i);
        if (!GetHasFeat(nFeatId, oPC)) continue;
        NWNX_Creature_RemoveFeat(oPC, nFeatId);
        nStray++;
    }

    LegFeat_ClearPicks(oPC);
    LegFeat_ClearAlloc(oPC);
    LegFeat_ApplyAll(oPC);          // clears any EFFECT-kind effects too
    ExportSingleCharacter(oPC);

    if (nStray > 0)
        SendMessageToPC(oPC, "Removed " + IntToString(nStray)
            + " legendary feat(s) with no pick record - ability scores were left "
            + "alone, since nothing recorded granting those points.");

    return nRecorded + nStray;
}

// Player-facing re-pick: hand every legendary feat back and let them be chosen
// again, without touching the character's level.
//
// Returns TRUE if the picker should now be opened.
//
// THE EXPLOIT THIS HAS TO NOT BE. A re-pick is only safe while giving a feat
// back is exactly as complete as taking it: the feat comes off AND the base
// ability points come off. LegFeat_RevokeAll does both from the pick records,
// so the round trip nets to zero - swap Legendary Strength for Legendary
// Wisdom and you are +6 WIS, not +6 to both. The failure to look for when
// touching any of this is a path that removes the feat but leaves the points.
//
// Refused while polymorphed for the same reason (see LegFeat_IsPolymorphed):
// the subtraction would land on a body that is about to be replaced.
int LegFeat_Respec(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return FALSE;

    if (LegFeat_TrueLevel(oPC) < LEGFEAT_LEVEL)
    {
        SendMessageToPC(oPC, "Legendary feats are chosen at level "
            + IntToString(LEGFEAT_LEVEL) + ".");
        return FALSE;
    }
    if (LegFeat_IsPolymorphed(oPC))
    {
        SendMessageToPC(oPC, "Return to your own shape first.");
        return FALSE;
    }

    LegFeat_InitDb();
    if (LegFeat_GetSpent(oPC) > 0)
        LegFeat_RevokeAll(oPC, "you asked to choose them again.");

    // Re-derives the allotment, so a character whose classes changed since the
    // last grant re-picks under the rules that apply now.
    LegFeat_EnsureAllotment(oPC);
    return TRUE;
}
