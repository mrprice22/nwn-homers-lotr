// legfeat_inc.nss — Legendary Feats: allotment, granting, and effects.
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
// magic fallback. Picks are permanent.
//
// EFFECTS AND WHY THEY ARE EFFECTS, NOT SKIN ITEM PROPERTIES. The design note
// pencilled ability bonuses in as item properties on the PC's creature-armour
// "skin". They are permanent supernatural effects instead, for two reasons
// found while building this:
//
//   1. PCs in this module have no skin. Nothing creates one, so the feature
//      would have to mint and manage a hide item per character.
//   2. sd_filter_inc.nss DESTROYS the creature-armour item on shapeshift
//      (line ~891). A druid or shifter would silently lose every legendary
//      ability bonus the first time they changed shape, and get it back only on
//      relog.
//
// A permanent supernatural effect survives rest and dispel, shows on the
// character sheet, and is re-applied at login by LegFeat_ApplyAll. The one thing
// it does NOT survive is a logout, which is exactly why the login hook exists.
//
// THE FAILURE MODE THIS FILE IS BUILT AROUND: the *feat* persists in the .bic
// but its *effects* do not. If nothing re-applies them at login, the bonus
// quietly stops showing on the character sheet and nothing errors. Every effect
// this file applies is tagged LEGFEAT_EFFECT_TAG so LegFeat_ApplyAll can clear
// and rebuild the whole set idempotently.

#include "legfeat_ids_inc"
#include "legfeat_db"
#include "nwnx_creature"

const int    LEGFEAT_LEVEL      = 60;              // picks unlock at exactly 60
const string LEGFEAT_EFFECT_TAG = "LEGFEAT_EFF";   // every effect we apply

int  LegFeat_Allotment(object oPC);
int  LegFeat_Remaining(object oPC);
int  LegFeat_EnsureAllotment(object oPC);
int  LegFeat_IndexOf(int nFeatId);
int  LegFeat_Take(object oPC, int nIndex);
void LegFeat_ApplyOne(object oPC, int nFeatId);
void LegFeat_ApplyAll(object oPC);

// How many picks this character's class spread is worth. Reads class levels, so
// it is correct whatever order the levels were taken in.
int LegFeat_Allotment(object oPC)
{
    int nClass1 = GetClassByPosition(1, oPC);
    int nLvl2   = GetLevelByPosition(2, oPC);
    int nLvl3   = GetLevelByPosition(3, oPC);
    int nLvl4   = GetLevelByPosition(4, oPC);

    // Mixed class: anything in a second, third or fourth class slot.
    if (nLvl2 > 0 || nLvl3 > 0 || nLvl4 > 0) return 1;

    if (nClass1 == CLASS_TYPE_FIGHTER) return 3;
    return 2;
}

// Picks granted but not yet spent.
int LegFeat_Remaining(object oPC)
{
    int n = LegFeat_GetGranted(oPC) - LegFeat_GetSpent(oPC);
    return (n > 0) ? n : 0;
}

// Grant the allotment if this character is level 60 and has not been granted
// one yet. Returns the number of picks now outstanding.
//
// Safe to call repeatedly — from the level-up hook, from login, and from the
// rest menu — because the allotment row is keyed on the character and written
// with a fixed value rather than incremented.
int LegFeat_EnsureAllotment(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return 0;
    if (GetHitDice(oPC) < LEGFEAT_LEVEL) return 0;

    LegFeat_InitDb();
    if (LegFeat_GetGranted(oPC) <= 0)
        LegFeat_SetGranted(oPC, LegFeat_Allotment(oPC));

    return LegFeat_Remaining(oPC);
}

// Picker index (0..LEGFEAT_COUNT-1) for a feat id, or -1 if it is not ours.
int LegFeat_IndexOf(int nFeatId)
{
    int n = nFeatId - LEGFEAT_FIRST;
    if (n < 0 || n >= LEGFEAT_COUNT) return -1;
    return n;
}

// Apply one feat's effect. Idempotence is the caller's job (LegFeat_ApplyAll
// clears the tagged set first); this only ever adds.
void LegFeat_ApplyOne(object oPC, int nFeatId)
{
    int nIndex = LegFeat_IndexOf(nFeatId);
    if (nIndex < 0) return;

    int nAbility = LegFeat_AbilityAt(nIndex);
    int nBonus   = LegFeat_BonusAt(nIndex);
    if (nAbility < 0 || nBonus <= 0) return;   // not an ability feat (yet)

    effect eAbil = EffectAbilityIncrease(nAbility, nBonus);
    eAbil = SupernaturalEffect(eAbil);          // survives rest and dispel
    eAbil = TagEffect(eAbil, LEGFEAT_EFFECT_TAG);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eAbil, oPC);
}

// Clear and rebuild every legendary effect on this character from the DB.
//
// Call at login and after any grant. Clearing first is what makes it safe to
// call twice — without it, a second call would stack a second +6.
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
        int nFeatId = LegFeat_IdAt(i);
        if (LegFeat_HasPick(oPC, nFeatId))
            LegFeat_ApplyOne(oPC, nFeatId);
    }
}

// Spend one pick on the feat at picker index nIndex.
//
// Returns TRUE if the feat was taken. Every rejection path is silent-safe: the
// caller reports, and nothing is half-applied (the DB row and the feat go
// together, and the effect is rebuilt from the DB afterwards).
int LegFeat_Take(object oPC, int nIndex)
{
    int nFeatId = LegFeat_IdAt(nIndex);
    if (nFeatId < 0) return FALSE;
    if (GetHitDice(oPC) < LEGFEAT_LEVEL) return FALSE;
    if (LegFeat_Remaining(oPC) <= 0) return FALSE;
    if (LegFeat_HasPick(oPC, nFeatId)) return FALSE;
    if (GetHasFeat(nFeatId, oPC)) return FALSE;   // belt and braces vs a DM grant

    NWNX_Creature_AddFeat(oPC, nFeatId);
    LegFeat_RecordPick(oPC, nFeatId);
    LegFeat_ApplyAll(oPC);
    return TRUE;
}
