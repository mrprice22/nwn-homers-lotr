//::///////////////////////////////////////////////
//:: shape_merge_inc
//:: Shared equipment-merge helper for all player polymorphs.
//:://////////////////////////////////////////////
/*
    Roadmap item wildshape-shifter-item-merge: merge ALL equipped item
    properties into every druid/shifter/arcane polymorph form, including
    weapon -> claw/bite creature weapons (vanilla only ever merged onto the
    new right-hand item, so animal forms never benefited from a weapon).

    Power balance: merged properties are bounded by the player's own
    forge-capped gear, and duplicate property types on a single item take
    highest-only, so hide-merging yields the best item of each kind rather
    than a stacked sum.

    Roadmap item shifter-stats-defect adds the other half. Merging properties
    was not enough, for two reasons:

      1. EffectPolymorph SETS base STR/CON/DEX from polymorph.2da (wolf
         13/15/15, ancient dragon 48/32/36). This server runs to level 60 with
         max-ability-bonus 24, so every form's numbers sit at or below a real
         character's own base scores and shifting was a DOWNGRADE. It also
         does not repay the BASE armour class of the armour and shield that
         stop applying - only their properties merge, never plate's own 8 AC.
      2. Creature weapons ignore ITEM_PROPERTY_ENHANCEMENT_BONUS for attack
         and damage rolls (it only buys damage-reduction bypass), so a +9
         weapon merged onto a claw paid out nothing. Players saw exactly this:
         "they are [passed through] for the shapes with weapons, the rest only
         get the damage".

    The rule ShapeMergeStatFloor implements: a geared character gets the same
    shape bonus a naked one would get under stock rules, on top of their own
    stats, measured from a stock-rules caster baseline of SHAPE_BASE_ANCHOR.

        form_bonus  = max(0, polymorph.2da value - SHAPE_BASE_ANCHOR)
        base target = own base + form_bonus       (never below own base)
        AC target   = unshifted AC + form NATURALACBONUS

    So brown bear (27/19/13) is +15/+7/+1 on top of what you already have,
    ancient dragon (48/32/36) is +36/+20/+24, and a badger (STR 8) is +0 -
    weak forms stay weak, strong forms are worth shifting into.

    Roadmap item tensors-transformation-not-merging-items-reliably adds the
    third piece: WHEN the merge is allowed to run. The engine does not always
    finish stripping the caster's gear and equipping the form's items within
    the same script tick that applies EffectPolymorph, so a merge done inline
    could read the PRE-shift slots - no creature hide (nothing merged at all)
    and the caster's own weapon still in the right hand. That second case was
    the dangerous one: IPWildShapeCopyItemProperties(oWeapon, oWeapon) copies
    an item's properties onto ITSELF as DURATION_TYPE_PERMANENT, quietly
    duplicating them in the player's .bic. Sync reported the visible half of
    it on Tenser's Transformation - "no buffs, no merge", the merge working
    only when four buffs had been cast first, i.e. only when the caster stood
    idle long enough for the swap to resolve.

    Two defences, because one is not enough:

      1. ShapeMergeWhenReady() is the entry point every caster script uses.
         It merges as soon as the form's own items are in the equipment slots,
         and keeps watching on a ladder out to 9s. Each ITEM it writes to is
         tagged with the shift's sequence number (SHAPE_VAR_CLAIM), so a target
         is merged at most once per shift however many rungs run.
      2. ShapeMergeAll() refuses any target that is one of the snapshot's own
         items, so a caller that merges too early gets "nothing merged"
         instead of a corrupted weapon.

    ROUND 2, and the reason this file reads the way it does. The first attempt
    used GetAppearanceType() as the "the form is on" signal and changed nothing
    at all - Sync retested and got the same buff-dependent behaviour. The
    engine flips the APPEARANCE and swaps the EQUIPMENT in separate ticks, and
    on Tenser's the appearance usually lands first:

        rung fires -> appearance already 40 -> "ready" -> PENDING cleared to 0
        -> ShapeMergeAll sees the caster's own weapon in the right hand and no
        form hide -> own-gear guard blanks both -> nothing merged, no message
        -> every later rung no-ops because PENDING is already spent.

    So the ladder was dead on arrival in exactly the case it was added for.
    Two corrections, and both are needed:

      - readiness is now "one of the slots polymorph.2da names for this form
        (HideItem, EQUIPPED, CreatureWeapon1-3) holds an item that is not one
        of the caster's own", falling back to appearance only for a row that
        names no items at all;
      - the one-shot is spent only when ShapeMergeAll actually merged
        something, so a ready-but-empty attempt leaves the ladder armed.

    ROUND 3. With the above in, the merge fires reliably - Sync's instrumented
    cold cast showed "ready=1 merged=1" on the first rung with no buffs at all,
    which round 1 and 2 never managed. What it does NOT yet do is deliver the
    gear's ABILITY bonuses: the same character read STR 26 / WIS 8 / CHA 8 on a
    cold cast and STR 43 / WIS 18 / CHA 14 on a later one, and since none of
    Elemental Shield, Shadow Shield or Mestil's Acid Sheath grants ability
    points, that spread can only be the equipment's own bonuses arriving in one
    case and not the other.

    Two candidates remain, and they need different fixes, so this round is
    built to tell them apart rather than to guess a third time:

      a. the merge lands on a hide the engine then tears down and rebuilds, so
         the properties are thrown away moments later;
      b. the merge lands and stays, but AddItemProperty on an already-equipped
         creature hide does not re-apply its ability bonuses.

    The per-item claim tag distinguishes them AND fixes (a) for free: the
    ladder keeps running after a successful merge, and a rung that finds an
    unclaimed hide has caught the engine swapping the item underneath us and
    merges the replacement. If (b) is the truth instead, the debug line will
    show the hide holding its merged property count all the way to the 9s rung
    while str/wis/cha never move - and the fix is a re-equip, not a re-merge.

    ROUND 4. Rounds 1-3 were all about WHEN the merge runs; this one is about
    WHAT it writes. Sync confirmed every merged property now reaches the
    character sheet except one: the enhancement bonus. Examining the shifted
    sword shows why - it carries the form weapon's own +3 (stock NW_WSWMLS013)
    AND the caster's +15, and the engine pays out the +3. Two generic
    enhancement bonuses on one item do not stack, and a generic Attack Bonus
    does not stack with the enhancement's attack component either, which is the
    same non-stacking pair the ab-enhance-stack-bug work collapsed across the
    module's weapon blueprints.

    IPWildShapeCopyItemProperties adds every source property blindly, so it can
    only ever produce that collision. The merge now splits in two:
    ShapeCopyPropsExceptBonus for everything that really does just add, and
    ShapeMergeWeaponBonus to RESOLVE the attack bonus down to a single property
    - the better of the form weapon's own and the caster's, with the loser
    removed rather than left to shadow it. On a creature weapon the same split
    keeps a single attack bonus and a single enhancement bonus, because there
    the two genuinely do not overlap: the enhancement buys only DR bypass.

    The corresponding assumption on the other side - that a player-accessible
    weapon never carries both bonuses at once - is now a build gate,
    tests/check_ab_enhance.py. It was not one before, and three obtainable
    weapons were violating it.

    For reference, the row this was chased on - stock polymorph.2da 28,
    POLYMORPH_DOOM_KNIGHT: AppearanceType 40, HideItem NW_IT_CREITEM005,
    EQUIPPED NW_WSWMLS013, no creature weapons, MergeW/MergeI/MergeA all blank
    (which is why the engine contributes no merge of its own here).

    Used by: nw_s2_wildshape, nw_s2_elemshape, x2_s2_gwildshp,
             nw_s0_polyself, nw_s0_shapechg, nw_s0_tenstrans
*/
//:://////////////////////////////////////////////

#include "x2_inc_itemprop"

// Tunables (compile-time; flip for future balance passes)
const int SHAPE_MERGE_WEAPON = TRUE;  // weapon -> right hand + claws/bite
const int SHAPE_MERGE_ARMOR  = TRUE;  // armor/helm/shield -> hide
const int SHAPE_MERGE_ITEMS  = TRUE;  // rings/amulet/cloak/boots/belt/gloves -> hide
const int SHAPE_MERGE_STATS  = TRUE;  // own base + the form's vanilla bonus

// Translate a merged weapon's enhancement bonus into attack + physical damage
// on creature weapons, which the engine otherwise ignores for both. Flip to
// FALSE if UAT ever shows a +9 weapon giving +18 on claws (that would mean the
// engine started honouring enhancement there, and this would double-count).
const int SHAPE_MERGE_ENH_AS_ATTACK = TRUE;

// The stock-rules score each form's bonus is measured from: a vanilla caster's
// 12 in the physical abilities. One knob retunes the whole system.
const int SHAPE_BASE_ANCHOR = 12;

// Per-ability ceiling on the top-up, purely defensive against a garbage 2DA
// read. Nothing legitimate comes close: the largest real gap is a level-60
// character in a wolf (base ~45 vs the form's 13).
const int SHAPE_TOPUP_MAX = 60;

// EffectAbilityIncrease counts against the server's max-ability-bonus (24) -
// the trap that made Legendary Feats abandon it for raw score writes. Stacked
// supernatural effects bypass that cap (mw_unlock_inc uses the same trick), so
// the top-up is emitted in chunks of this size.
const int SHAPE_TOPUP_CHUNK = 6;

// Temporary instrumentation. Set on the module object by dbg_combat (rest menu
// -> Admin Options -> "[Admin] Combat diagnostics on/off"), which is already
// gated on the admindb whitelist - so nothing here needs to read admindb, and
// the six spell scripts that include this file stay free of a DB hit.
//
// When it is on, every rung of the merge ladder reports what it saw in the
// equipment slots. Delete this constant, ShapeMergeDebug(), the three call
// sites and the dbg_combat line once tensors-transformation-not-merging-items
// -reliably is closed.
const string SHAPE_VAR_DEBUG = "SHAPE_MERGE_DEBUG";

// Snapshot of pre-polymorph equipment, taken before EffectPolymorph is applied.
struct ShapeMergeGear
{
    object oWeapon;
    object oArmor;
    object oHelmet;
    object oShield;
    object oRing1;
    object oRing2;
    object oAmulet;
    object oCloak;
    object oBoots;
    object oBelt;
    object oGloves;
};

// Capture oShifter's equipped items. Call BEFORE applying the polymorph
// effect. Non-shield left-hand items are dropped from the snapshot,
// matching vanilla behavior.
struct ShapeMergeGear ShapeMergeSnapshot(object oShifter);

// Merge the snapshot's item properties onto oShifter's post-polymorph
// creature items. Call AFTER applying the polymorph effect. Returns TRUE only
// if something of the FORM's was actually written to.
//
// Prefer ShapeMergeWhenReady() - calling this directly merges whatever is in
// the slots RIGHT NOW, which is not necessarily the form (see the file header).
int ShapeMergeAll(object oShifter, struct ShapeMergeGear gear, int nSeq = 0);

// TRUE once the engine has actually put oShifter's FORM ITEMS in the slots.
//
// Appearance is not that signal, which is what round 1 of this fix got wrong:
// the engine flips the appearance and swaps the equipment in separate ticks,
// so an appearance-only gate opens while the caster's own gear is still on.
// The honest question is whether one of the slots polymorph.2da names for this
// form (HideItem, EQUIPPED, CreatureWeapon1-3) now holds an item that is not
// one of the caster's own.
int ShapeMergeFormReady(object oShifter, int nPoly, struct ShapeMergeGear gear);

// The entry point every polymorph script should use. Merges immediately when
// the form's items are already in the slots, otherwise retries on a ladder out
// to 6s until they are, and never merges more than once per shift.
void ShapeMergeWhenReady(object oShifter, int nPoly, struct ShapeMergeGear gear);

// Returns ePoly with the stat top-ups linked into it, so that shifting adds
// the form's stock bonus to what oShifter already has instead of replacing it.
// Call AFTER ShapeMergeSnapshot and BEFORE the polymorph is applied, and apply
// the RETURNED effect. Linking is what makes this exploit-proof: unshifting,
// dispelling or the duration expiring takes the top-ups with the form, so
// nothing can survive into unshifted play.
effect ShapeMergeStatFloor(object oShifter, int nPoly, effect ePoly,
                           struct ShapeMergeGear gear);


struct ShapeMergeGear ShapeMergeSnapshot(object oShifter)
{
    struct ShapeMergeGear gear;
    gear.oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oShifter);
    gear.oArmor  = GetItemInSlot(INVENTORY_SLOT_CHEST, oShifter);
    gear.oHelmet = GetItemInSlot(INVENTORY_SLOT_HEAD, oShifter);
    gear.oShield = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oShifter);
    gear.oRing1  = GetItemInSlot(INVENTORY_SLOT_LEFTRING, oShifter);
    gear.oRing2  = GetItemInSlot(INVENTORY_SLOT_RIGHTRING, oShifter);
    gear.oAmulet = GetItemInSlot(INVENTORY_SLOT_NECK, oShifter);
    gear.oCloak  = GetItemInSlot(INVENTORY_SLOT_CLOAK, oShifter);
    gear.oBoots  = GetItemInSlot(INVENTORY_SLOT_BOOTS, oShifter);
    gear.oBelt   = GetItemInSlot(INVENTORY_SLOT_BELT, oShifter);
    gear.oGloves = GetItemInSlot(INVENTORY_SLOT_ARMS, oShifter);

    if (GetIsObjectValid(gear.oShield))
    {
        if (GetBaseItemType(gear.oShield) != BASE_ITEM_LARGESHIELD &&
            GetBaseItemType(gear.oShield) != BASE_ITEM_SMALLSHIELD &&
            GetBaseItemType(gear.oShield) != BASE_ITEM_TOWERSHIELD)
        {
            gear.oShield = OBJECT_INVALID;
        }
    }
    return gear;
}

// One polymorph.2da cell as an int. A blank ("****") column means the form
// keeps the character's own value, and Get2DAString gives "" for it.
int ShapeFormStat(int nPoly, string sColumn)
{
    string sVal = Get2DAString("polymorph", sColumn, nPoly);
    if (sVal == "") return 0;
    return StringToInt(sVal);
}

// One polymorph.2da cell as a resref-ish string, "" for a blank ("****")
// column. Used to ask which item slots this form is going to fill.
string ShapeFormString(int nPoly, string sColumn)
{
    return Get2DAString("polymorph", sColumn, nPoly);
}

// Flat amount -> IP_CONST_DAMAGEBONUS_* constant.
//
// NOT the same table as DAMAGE_BONUS_* (the effect constants that
// IPGetDamageBonusConstantFromNumber returns): on the item-property side 6..10
// are 16..20, and 6..15 are DICE. Feeding a raw int to ItemPropertyDamageBonus
// turns a promised flat +7 into 1d6 - the same trap bonus_pool_inc documents
// for the effect side. Item properties top out at a flat +10.
int ShapeDamageIPConst(int nAmount)
{
    if (nAmount > 10) nAmount = 10;
    switch (nAmount)
    {
        case 1:  return IP_CONST_DAMAGEBONUS_1;
        case 2:  return IP_CONST_DAMAGEBONUS_2;
        case 3:  return IP_CONST_DAMAGEBONUS_3;
        case 4:  return IP_CONST_DAMAGEBONUS_4;
        case 5:  return IP_CONST_DAMAGEBONUS_5;
        case 6:  return IP_CONST_DAMAGEBONUS_6;
        case 7:  return IP_CONST_DAMAGEBONUS_7;
        case 8:  return IP_CONST_DAMAGEBONUS_8;
        case 9:  return IP_CONST_DAMAGEBONUS_9;
        case 10: return IP_CONST_DAMAGEBONUS_10;
    }
    return -1;
}

// The physical damage type an enhancement bonus would add to on this claw.
int ShapeClawDamageType(object oClaw)
{
    switch (GetBaseItemType(oClaw))
    {
        case BASE_ITEM_CPIERCWEAPON: return IP_CONST_DAMAGETYPE_PIERCING;
        case BASE_ITEM_CBLUDGWEAPON: return IP_CONST_DAMAGETYPE_BLUDGEONING;
    }
    // CSLASHWEAPON, CSLSHPRCWEAP and anything unexpected
    return IP_CONST_DAMAGETYPE_SLASHING;
}

// The two generic "how hard do I hit" item properties. They are the generic
// types: the conditional variants (vs racial group, vs alignment group, vs
// specific alignment) are SEPARATE property types, so matching on the type
// alone is exactly right here and needs no subtype test - which also sidesteps
// the trap the Python tooling hit, where a blank subtype is encoded as either
// 0 or 65535 (see generic_value() in bin/ab-enhance-audit.py).
//
// Neither stacks with the other, and neither stacks with a second copy of
// itself. That is the whole of the round-4 defect: the merge used to add the
// caster's +15 alongside the form weapon's stock +3 and the engine paid out
// the +3.

// Highest +N carried by oItem for property type nType, 0 if it has none.
int ShapeIPMax(object oItem, int nType)
{
    if (!GetIsObjectValid(oItem)) return 0;

    int nMax = 0;
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyType(ip) == nType)
        {
            int nVal = GetItemPropertyCostTableValue(ip);
            if (nVal > nMax) nMax = nVal;
        }
        ip = GetNextItemProperty(oItem);
    }
    return nMax;
}

// Remove every property of type nType from oItem, whatever its duration. Same
// iterate-and-remove shape as IPRemoveMatchingItemProperties in x2_inc_itemprop
// and IPSetWeaponEnhancementBonus, which is what makes it safe on the PERMANENT
// properties a blueprint ships with.
void ShapeIPStrip(object oItem, int nType)
{
    if (!GetIsObjectValid(oItem)) return;

    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyType(ip) == nType)
            RemoveItemProperty(oItem, ip);
        ip = GetNextItemProperty(oItem);
    }
}

// IPWildShapeCopyItemProperties, minus the two bonuses above. Everything else
// merges the way it always has; the attack bonus is resolved separately by the
// callers, because it is the one property where "add both" is wrong.
void ShapeCopyPropsExceptBonus(object oSrc, object oDst, int bWeapon = FALSE)
{
    if (!GetIsObjectValid(oSrc) || !GetIsObjectValid(oDst)) return;
    if (bWeapon && GetWeaponRanged(oSrc) != GetWeaponRanged(oDst)) return;

    itemproperty ip = GetFirstItemProperty(oSrc);
    while (GetIsItemPropertyValid(ip))
    {
        int nType = GetItemPropertyType(ip);
        if (nType != ITEM_PROPERTY_ENHANCEMENT_BONUS &&
            nType != ITEM_PROPERTY_ATTACK_BONUS)
        {
            AddItemProperty(DURATION_TYPE_PERMANENT, ip, oDst);
        }
        ip = GetNextItemProperty(oSrc);
    }
}

// "enh15/ab0" - the two generic bonuses on one item, for the debug line.
string ShapeIPBonusDesc(object oItem)
{
    return "enh" + IntToString(ShapeIPMax(oItem, ITEM_PROPERTY_ENHANCEMENT_BONUS)) +
           "/ab" + IntToString(ShapeIPMax(oItem, ITEM_PROPERTY_ATTACK_BONUS));
}

// Resolve the attack bonus on a MANUFACTURED form weapon (Tenser's sword, the
// drow/azer blades) so that exactly ONE generic bonus survives on it: the
// better of the form weapon's own and the caster's.
//
// The rule, as reported by Sync and confirmed with the admin:
//   1. the caster's weapon wins only if its best bonus BEATS the form's, and
//      then the form's own enhancement AND attack bonus both come off;
//   2. otherwise nothing is copied at all and the form keeps its stock bonus.
// A caster's weapon carrying an attack bonus rather than an enhancement bonus
// therefore strips the form's +3 as well. That loses the +3's damage and
// damage-reduction bypass, and it is the deliberate choice: one property, one
// number, a character sheet that agrees with the examine text. Player weapons
// are not allowed to carry both bonuses at once - tests/check_ab_enhance.py is
// the build gate for that - so "the best of the two" is really just "the one".
void ShapeMergeWeaponBonus(object oSrc, object oDst)
{
    if (!GetIsObjectValid(oSrc) || !GetIsObjectValid(oDst)) return;
    if (GetWeaponRanged(oSrc) != GetWeaponRanged(oDst)) return;

    int nSrcEnh = ShapeIPMax(oSrc, ITEM_PROPERTY_ENHANCEMENT_BONUS);
    int nSrcAB  = ShapeIPMax(oSrc, ITEM_PROPERTY_ATTACK_BONUS);
    int nDstEnh = ShapeIPMax(oDst, ITEM_PROPERTY_ENHANCEMENT_BONUS);
    int nDstAB  = ShapeIPMax(oDst, ITEM_PROPERTY_ATTACK_BONUS);

    int nSrcBest = nSrcEnh; if (nSrcAB > nSrcBest) nSrcBest = nSrcAB;
    int nDstBest = nDstEnh; if (nDstAB > nDstBest) nDstBest = nDstAB;

    // The form's own bonus already wins - rule 2, copy nothing.
    if (nSrcBest <= nDstBest) return;

    ShapeIPStrip(oDst, ITEM_PROPERTY_ENHANCEMENT_BONUS);
    ShapeIPStrip(oDst, ITEM_PROPERTY_ATTACK_BONUS);

    if (nSrcEnh >= nSrcAB)
        AddItemProperty(DURATION_TYPE_PERMANENT,
                        ItemPropertyEnhancementBonus(nSrcEnh), oDst);
    else
        AddItemProperty(DURATION_TYPE_PERMANENT,
                        ItemPropertyAttackBonus(nSrcAB), oDst);
}

// Copy a weapon's properties onto one of the form's natural attacks.
//
// Same job as IPWildShapeCopyItemProperties(oSrc, oClaw, TRUE), plus the fix
// for shifter-stats-defect: creature weapons ignore an enhancement bonus for
// attack and damage rolls (it only buys damage-reduction bypass), so a merged
// +9 weapon paid out nothing on a claw or bite. Re-express the caster's best
// bonus as the +n attack it is supposed to be, plus the +n physical damage an
// enhancement would have given, and keep a single enhancement property for the
// DR bypass it still provides.
//
// A claw therefore ends up carrying BOTH an attack bonus and an enhancement
// bonus, which is exactly what check_ab_enhance.py forbids on a blueprint. The
// difference is real: on a creature weapon the two do not overlap at all, since
// the enhancement contributes nothing to the attack roll to be shadowed by.
void ShapeCopyToCreatureWeapon(object oSrc, object oClaw)
{
    if (!GetIsObjectValid(oSrc) || !GetIsObjectValid(oClaw)) return;

    // The ranged-mismatch guard: do not hand the form a bow's properties on
    // its claws. ShapeCopyPropsExceptBonus applies the same test itself.
    if (GetWeaponRanged(oSrc) != GetWeaponRanged(oClaw)) return;

    ShapeCopyPropsExceptBonus(oSrc, oClaw, TRUE);

    int nSrcEnh = ShapeIPMax(oSrc, ITEM_PROPERTY_ENHANCEMENT_BONUS);
    int nSrcAB  = ShapeIPMax(oSrc, ITEM_PROPERTY_ATTACK_BONUS);
    int nSrcBest = nSrcEnh; if (nSrcAB > nSrcBest) nSrcBest = nSrcAB;

    if (!SHAPE_MERGE_ENH_AS_ATTACK)
    {
        // Balance knob off: fall back to the vanilla behaviour of merging the
        // enhancement across verbatim and letting the engine ignore it.
        if (nSrcEnh > ShapeIPMax(oClaw, ITEM_PROPERTY_ENHANCEMENT_BONUS))
        {
            ShapeIPStrip(oClaw, ITEM_PROPERTY_ENHANCEMENT_BONUS);
            AddItemProperty(DURATION_TYPE_PERMANENT,
                            ItemPropertyEnhancementBonus(nSrcEnh), oClaw);
        }
        return;
    }

    // Attack: the claw keeps the higher of its own and the caster's, once.
    if (nSrcBest > ShapeIPMax(oClaw, ITEM_PROPERTY_ATTACK_BONUS))
    {
        ShapeIPStrip(oClaw, ITEM_PROPERTY_ATTACK_BONUS);
        AddItemProperty(DURATION_TYPE_PERMANENT,
                        ItemPropertyAttackBonus(nSrcBest), oClaw);
    }

    // Enhancement: DR bypass only on a creature weapon, so it is kept, but
    // only ever as a single property at the higher of the two values.
    if (nSrcEnh > ShapeIPMax(oClaw, ITEM_PROPERTY_ENHANCEMENT_BONUS))
    {
        ShapeIPStrip(oClaw, ITEM_PROPERTY_ENHANCEMENT_BONUS);
        AddItemProperty(DURATION_TYPE_PERMANENT,
                        ItemPropertyEnhancementBonus(nSrcEnh), oClaw);
    }

    // Damage: what the enhancement would have paid out on a real weapon. An
    // attack-bonus-only weapon grants no damage, on a claw or anywhere else.
    if (nSrcEnh > 0)
    {
        int nDamage = ShapeDamageIPConst(nSrcEnh);
        if (nDamage != -1)
            AddItemProperty(DURATION_TYPE_PERMANENT,
                ItemPropertyDamageBonus(ShapeClawDamageType(oClaw), nDamage),
                oClaw);
    }
}

// Link the top-up for one ability into eLink, per the rule in the file header:
// the character keeps their own base score and gains what the form is worth
// over a stock-rules character (SHAPE_BASE_ANCHOR).
effect ShapeAbilityTopUp(object oShifter, int nPoly, string sColumn,
                         int nAbility, effect eLink)
{
    int nForm = ShapeFormStat(nPoly, sColumn);
    if (nForm <= 0) return eLink;   // blank column: the form keeps your score

    int nBonus = nForm - SHAPE_BASE_ANCHOR;
    if (nBonus < 0) nBonus = 0;     // a weak form is not allowed to be a buff

    // The engine is about to set the base score to nForm, so the effect has to
    // carry the whole distance from there back up to the target.
    int nTopUp = GetAbilityScore(oShifter, nAbility, TRUE) + nBonus - nForm;
    if (nTopUp <= 0) return eLink;  // the form already beats the target
    if (nTopUp > SHAPE_TOPUP_MAX) nTopUp = SHAPE_TOPUP_MAX;

    while (nTopUp > 0)
    {
        int nChunk = nTopUp;
        if (nChunk > SHAPE_TOPUP_CHUNK) nChunk = SHAPE_TOPUP_CHUNK;
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(nAbility, nChunk));
        nTopUp -= nChunk;
    }
    return eLink;
}

effect ShapeMergeStatFloor(object oShifter, int nPoly, effect ePoly,
                           struct ShapeMergeGear gear)
{
    if (!SHAPE_MERGE_STATS) return ePoly;

    ePoly = ShapeAbilityTopUp(oShifter, nPoly, "STR", ABILITY_STRENGTH,     ePoly);
    ePoly = ShapeAbilityTopUp(oShifter, nPoly, "CON", ABILITY_CONSTITUTION, ePoly);
    ePoly = ShapeAbilityTopUp(oShifter, nPoly, "DEX", ABILITY_DEXTERITY,    ePoly);

    // Armour and shield stop applying while shifted. Their PROPERTIES merge
    // onto the hide, but plate's own 8 AC cannot - hand it back, on top of the
    // form's natural bonus, so AC ends up "your AC plus what the form adds".
    // Natural is the same bonus type the form's own NATURALACBONUS uses and
    // only the highest of a type counts, so this supersedes it rather than
    // stacking with it. It also sidesteps MAX_AC_DODGE_MOD, which would eat
    // part of an AC_DODGE_BONUS.
    int nLost = 0;
    if (GetIsObjectValid(gear.oArmor))  nLost += GetItemACValue(gear.oArmor);
    if (GetIsObjectValid(gear.oShield)) nLost += GetItemACValue(gear.oShield);

    if (nLost > 0)
        ePoly = EffectLinkEffects(ePoly,
            EffectACIncrease(ShapeFormStat(nPoly, "NATURALACBONUS") + nLost,
                             AC_NATURAL_BONUS));

    return ePoly;
}

// TRUE if oItem is one of the caster's own pre-shift items. Merging onto one
// of those is never right: at best it is a no-op, at worst it copies an item's
// properties onto itself, permanently, in the player's .bic.
int ShapeMergeIsOwnGear(object oItem, struct ShapeMergeGear gear)
{
    if (!GetIsObjectValid(oItem)) return FALSE;
    return oItem == gear.oWeapon || oItem == gear.oArmor  || oItem == gear.oHelmet ||
           oItem == gear.oShield || oItem == gear.oRing1  || oItem == gear.oRing2  ||
           oItem == gear.oAmulet || oItem == gear.oCloak  || oItem == gear.oBoots  ||
           oItem == gear.oBelt   || oItem == gear.oGloves;
}

// The merge marks every item it writes to with the shift's sequence number, so
// a target is merged at most once per shift NO MATTER how many rungs run. The
// tag rides the object, which is the point: if the engine tears the form's hide
// down and builds a fresh one after we merged, the replacement carries no tag
// and the next rung merges it properly. That is strictly better than the old
// PC-level one-shot, which could only ever say "already tried".
const string SHAPE_VAR_CLAIM = "SHAPE_MERGED_SEQ";

// TRUE if oItem has not been merged into for this shift yet; claims it if so.
int ShapeMergeClaim(object oItem, int nSeq)
{
    if (!GetIsObjectValid(oItem)) return FALSE;
    if (nSeq > 0 && GetLocalInt(oItem, SHAPE_VAR_CLAIM) == nSeq) return FALSE;
    if (nSeq > 0) SetLocalInt(oItem, SHAPE_VAR_CLAIM, nSeq);
    return TRUE;
}

// How many item properties oItem carries. Diagnostic only - it is how we tell
// "the merge never landed" from "the merge landed and was thrown away".
int ShapeMergePropCount(object oItem)
{
    if (!GetIsObjectValid(oItem)) return -1;
    int n = 0;
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        n++;
        ip = GetNextItemProperty(oItem);
    }
    return n;
}

// Temporary instrumentation - see SHAPE_VAR_DEBUG. Silent unless an admin has
// turned combat diagnostics on from the rest menu this boot.
void ShapeMergeDebug(object oShifter, string sMsg)
{
    if (!GetIsPC(oShifter)) return;
    if (!GetLocalInt(GetModule(), SHAPE_VAR_DEBUG)) return;
    SendMessageToPC(oShifter, "[SHAPE] " + sMsg);
}

// One equipment slot as "<resref>" / "<resref>(own)" / "-", for the debug line.
string ShapeMergeSlotDesc(object oShifter, int nSlot, struct ShapeMergeGear gear)
{
    object oItem = GetItemInSlot(nSlot, oShifter);
    if (!GetIsObjectValid(oItem)) return "-";
    if (ShapeMergeIsOwnGear(oItem, gear)) return GetResRef(oItem) + "(own)";
    return GetResRef(oItem);
}

// One snapshot slot as "<resref>[<property count>]" / "-".
string ShapeMergeGearDesc(object oItem)
{
    if (!GetIsObjectValid(oItem)) return "-";
    return GetResRef(oItem) + "[" + IntToString(ShapeMergePropCount(oItem)) + "]";
}

// "str=26/18 dex=23/15 ..." - current score over base score. The pair is what
// separates "the merge never delivered the gear's ability bonuses" from "the
// top-up computed the wrong target".
string ShapeMergeAbilityDesc(object oShifter)
{
    return
        " str=" + IntToString(GetAbilityScore(oShifter, ABILITY_STRENGTH, FALSE)) +
          "/"   + IntToString(GetAbilityScore(oShifter, ABILITY_STRENGTH, TRUE)) +
        " dex=" + IntToString(GetAbilityScore(oShifter, ABILITY_DEXTERITY, FALSE)) +
          "/"   + IntToString(GetAbilityScore(oShifter, ABILITY_DEXTERITY, TRUE)) +
        " con=" + IntToString(GetAbilityScore(oShifter, ABILITY_CONSTITUTION, FALSE)) +
          "/"   + IntToString(GetAbilityScore(oShifter, ABILITY_CONSTITUTION, TRUE)) +
        " wis=" + IntToString(GetAbilityScore(oShifter, ABILITY_WISDOM, FALSE)) +
          "/"   + IntToString(GetAbilityScore(oShifter, ABILITY_WISDOM, TRUE)) +
        " cha=" + IntToString(GetAbilityScore(oShifter, ABILITY_CHARISMA, FALSE)) +
          "/"   + IntToString(GetAbilityScore(oShifter, ABILITY_CHARISMA, TRUE));
}

int ShapeMergeAll(object oShifter, struct ShapeMergeGear gear, int nSeq = 0)
{
    object oWeaponNew = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oShifter);
    object oHideNew   = GetItemInSlot(INVENTORY_SLOT_CARMOUR, oShifter);

    // The swap has not happened (or this form keeps no such item) - whatever is
    // in these slots belongs to the character, not to the form.
    if (ShapeMergeIsOwnGear(oWeaponNew, gear)) oWeaponNew = OBJECT_INVALID;
    if (ShapeMergeIsOwnGear(oHideNew, gear))   oHideNew   = OBJECT_INVALID;

    // Already merged into on an earlier rung of THIS shift - leave it alone.
    // A hide the engine rebuilt since then is a different object and so is not
    // claimed, which is exactly when we do want to merge again.
    if (!ShapeMergeClaim(oWeaponNew, nSeq)) oWeaponNew = OBJECT_INVALID;
    if (!ShapeMergeClaim(oHideNew, nSeq))   oHideNew   = OBJECT_INVALID;

    if (GetIsObjectValid(oWeaponNew))
        SetIdentified(oWeaponNew, TRUE);

    int bMergedSomething = FALSE;

    if (SHAPE_MERGE_WEAPON)
    {
        // Unarmed casters: let glove properties ride the natural attacks.
        object oWeaponSrc = gear.oWeapon;
        int bGlovesAsWeapon = FALSE;
        if (!GetIsObjectValid(oWeaponSrc) && GetIsObjectValid(gear.oGloves))
        {
            oWeaponSrc = gear.oGloves;
            bGlovesAsWeapon = TRUE;
        }

        if (GetIsObjectValid(oWeaponSrc))
        {
            // Vanilla path: forms with a manufactured weapon (drow, azer...).
            // oWeaponNew is OBJECT_INVALID unless it really is the form's -
            // the helpers no-op on it then, and the natural attacks below are
            // the only merge target.
            //
            // Two calls, because the attack bonus cannot just be added on top
            // of the form weapon's own: see ShapeMergeWeaponBonus.
            ShapeCopyPropsExceptBonus(oWeaponSrc, oWeaponNew, TRUE);
            ShapeMergeWeaponBonus(oWeaponSrc, oWeaponNew);

            // New: natural attacks. Gloves carry no ranged flag, so the
            // helper's ranged-mismatch guard still applies for real weapons.
            // ShapeCopyToCreatureWeapon also re-expresses the enhancement
            // bonus, which creature weapons otherwise ignore.
            object oClawL = GetItemInSlot(INVENTORY_SLOT_CWEAPON_L, oShifter);
            object oClawR = GetItemInSlot(INVENTORY_SLOT_CWEAPON_R, oShifter);
            object oClawB = GetItemInSlot(INVENTORY_SLOT_CWEAPON_B, oShifter);
            if (!ShapeMergeClaim(oClawL, nSeq)) oClawL = OBJECT_INVALID;
            if (!ShapeMergeClaim(oClawR, nSeq)) oClawR = OBJECT_INVALID;
            if (!ShapeMergeClaim(oClawB, nSeq)) oClawB = OBJECT_INVALID;
            ShapeCopyToCreatureWeapon(oWeaponSrc, oClawL);
            ShapeCopyToCreatureWeapon(oWeaponSrc, oClawR);
            ShapeCopyToCreatureWeapon(oWeaponSrc, oClawB);

            // Only true if there was something of the form's to merge ONTO.
            if (GetIsObjectValid(oWeaponNew) || GetIsObjectValid(oClawL) ||
                GetIsObjectValid(oClawR) || GetIsObjectValid(oClawB))
                bMergedSomething = TRUE;
        }

        if (bGlovesAsWeapon)
            gear.oGloves = OBJECT_INVALID; // don't also merge them onto the hide
    }

    if (SHAPE_MERGE_ARMOR && GetIsObjectValid(oHideNew))
    {
        IPWildShapeCopyItemProperties(gear.oArmor,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oHelmet, oHideNew);
        IPWildShapeCopyItemProperties(gear.oShield, oHideNew);
        if (GetIsObjectValid(gear.oArmor) || GetIsObjectValid(gear.oHelmet) ||
            GetIsObjectValid(gear.oShield))
            bMergedSomething = TRUE;
    }

    if (SHAPE_MERGE_ITEMS && GetIsObjectValid(oHideNew))
    {
        IPWildShapeCopyItemProperties(gear.oRing1,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oRing2,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oAmulet, oHideNew);
        IPWildShapeCopyItemProperties(gear.oCloak,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oBoots,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oBelt,   oHideNew);
        IPWildShapeCopyItemProperties(gear.oGloves, oHideNew);
        if (GetIsObjectValid(gear.oRing1) || GetIsObjectValid(gear.oRing2) ||
            GetIsObjectValid(gear.oAmulet) || GetIsObjectValid(gear.oCloak) ||
            GetIsObjectValid(gear.oBoots) || GetIsObjectValid(gear.oBelt) ||
            GetIsObjectValid(gear.oGloves))
            bMergedSomething = TRUE;
    }

    if (bMergedSomething && GetIsPC(oShifter) &&
        GetLocalInt(oShifter, "SHAPE_MERGE_TOLD") != nSeq)
    {
        SetLocalInt(oShifter, "SHAPE_MERGE_TOLD", nSeq);
        FloatingTextStringOnCreature(
            "Your equipment's magic flows into your new form.", oShifter, FALSE);
    }

    return bMergedSomething;
}

// TRUE if the form names an item for nSlot and something that is NOT one of
// the caster's own is now sitting there. Identity against the snapshot is the
// load-bearing test: it is what separates the form's hide from the caster's
// breastplate, which a resref comparison alone would not do for a shifter
// wearing a creature item.
int ShapeMergeFormItemHere(object oShifter, int nSlot, string sResRef,
                           struct ShapeMergeGear gear)
{
    if (sResRef == "") return FALSE;    // the form fills no such slot
    object oItem = GetItemInSlot(nSlot, oShifter);
    if (!GetIsObjectValid(oItem)) return FALSE;
    return !ShapeMergeIsOwnGear(oItem, gear);
}

int ShapeMergeFormReady(object oShifter, int nPoly, struct ShapeMergeGear gear)
{
    string sHide  = ShapeFormString(nPoly, "HideItem");
    string sEquip = ShapeFormString(nPoly, "EQUIPPED");
    string sCw1   = ShapeFormString(nPoly, "CreatureWeapon1");
    string sCw2   = ShapeFormString(nPoly, "CreatureWeapon2");
    string sCw3   = ShapeFormString(nPoly, "CreatureWeapon3");

    // A row that names no items has nothing for the ladder to wait on. Fall
    // back to appearance rather than stalling forever - there is nothing to
    // merge onto in that case anyway.
    if (sHide == "" && sEquip == "" && sCw1 == "" && sCw2 == "" && sCw3 == "")
    {
        int nAppearance = ShapeFormStat(nPoly, "AppearanceType");
        if (nAppearance <= 0) return TRUE;
        return GetAppearanceType(oShifter) == nAppearance;
    }

    if (ShapeMergeFormItemHere(oShifter, INVENTORY_SLOT_CARMOUR,   sHide,  gear))
        return TRUE;
    if (ShapeMergeFormItemHere(oShifter, INVENTORY_SLOT_RIGHTHAND, sEquip, gear))
        return TRUE;
    if (ShapeMergeFormItemHere(oShifter, INVENTORY_SLOT_CWEAPON_R, sCw1, gear))
        return TRUE;
    if (ShapeMergeFormItemHere(oShifter, INVENTORY_SLOT_CWEAPON_L, sCw2, gear))
        return TRUE;
    if (ShapeMergeFormItemHere(oShifter, INVENTORY_SLOT_CWEAPON_B, sCw3, gear))
        return TRUE;

    return FALSE;
}

// One attempt in the ladder ShapeMergeWhenReady lays down. Non-recursive on
// purpose - NWScript forbids a function calling itself, DelayCommand included.
void ShapeMergeAttempt(object oShifter, int nPoly, struct ShapeMergeGear gear,
                       int nSeq)
{
    // Only a LATER shift retires this ladder. Every rung runs to the end of the
    // ladder even after a successful merge: the per-target claim tag makes a
    // repeat a no-op, and the one case where a repeat is NOT a no-op - the
    // engine having rebuilt the form's hide underneath us, so the replacement
    // carries no tag - is exactly the case worth catching.
    if (GetLocalInt(oShifter, "SHAPE_MERGE_SEQ") != nSeq) return;

    int bReady  = ShapeMergeFormReady(oShifter, nPoly, gear);
    int bMerged = FALSE;
    if (bReady) bMerged = ShapeMergeAll(oShifter, gear, nSeq);

    object oRH   = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oShifter);
    object oHide = GetItemInSlot(INVENTORY_SLOT_CARMOUR, oShifter);

    // Round 4: the two generic bonuses on the caster's weapon and on whatever
    // is in the right hand now. "src(enh15/ab0) rh(enh15/ab0)" is the merge
    // having resolved; "rh(enh3/ab0)" against a bigger src is it having lost.
    string sBonus = " bonus=src(" + ShapeIPBonusDesc(gear.oWeapon) +
                    ") rh(" + ShapeIPBonusDesc(oRH) + ")";

    ShapeMergeDebug(oShifter,
        "seq=" + IntToString(nSeq) + " poly=" + IntToString(nPoly) +
        " appear=" + IntToString(GetAppearanceType(oShifter)) +
        "/" + IntToString(ShapeFormStat(nPoly, "AppearanceType")) +
        " rh="   + ShapeMergeSlotDesc(oShifter, INVENTORY_SLOT_RIGHTHAND, gear) +
          "[" + IntToString(ShapeMergePropCount(oRH)) + "]" +
        " hide=" + ShapeMergeSlotDesc(oShifter, INVENTORY_SLOT_CARMOUR, gear) +
          "[" + IntToString(ShapeMergePropCount(oHide)) + "]" +
        " cwR="  + ShapeMergeSlotDesc(oShifter, INVENTORY_SLOT_CWEAPON_R, gear) +
        " cwL="  + ShapeMergeSlotDesc(oShifter, INVENTORY_SLOT_CWEAPON_L, gear) +
        " cwB="  + ShapeMergeSlotDesc(oShifter, INVENTORY_SLOT_CWEAPON_B, gear) +
        sBonus +
        " ready=" + IntToString(bReady) + " merged=" + IntToString(bMerged) +
        ShapeMergeAbilityDesc(oShifter));
}

void ShapeMergeWhenReady(object oShifter, int nPoly, struct ShapeMergeGear gear)
{
    int nSeq = GetLocalInt(oShifter, "SHAPE_MERGE_SEQ") + 1;
    SetLocalInt(oShifter, "SHAPE_MERGE_SEQ", nSeq);

    ShapeMergeDebug(oShifter, "cast seq=" + IntToString(nSeq) +
        " poly=" + IntToString(nPoly) +
        " wpn="    + ShapeMergeGearDesc(gear.oWeapon) +
        " armor="  + ShapeMergeGearDesc(gear.oArmor) +
        " helm="   + ShapeMergeGearDesc(gear.oHelmet) +
        " shield=" + ShapeMergeGearDesc(gear.oShield) +
        " ring1="  + ShapeMergeGearDesc(gear.oRing1) +
        " ring2="  + ShapeMergeGearDesc(gear.oRing2) +
        " neck="   + ShapeMergeGearDesc(gear.oAmulet) +
        " cloak="  + ShapeMergeGearDesc(gear.oCloak) +
        " boots="  + ShapeMergeGearDesc(gear.oBoots) +
        " belt="   + ShapeMergeGearDesc(gear.oBelt) +
        " gloves=" + ShapeMergeGearDesc(gear.oGloves) +
        ShapeMergeAbilityDesc(oShifter));

    // Usually the swap is already done and the first rung is the one that
    // merges. The rest are headroom, and - since round 3 - a watch: a rung
    // after the merge that finds an UNCLAIMED hide has caught the engine
    // replacing the item we merged into, and merges the replacement.
    ShapeMergeAttempt(oShifter, nPoly, gear, nSeq);

    DelayCommand(0.2, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(0.5, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(1.0, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(1.5, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(2.5, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(4.0, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(6.0, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
    DelayCommand(9.0, ShapeMergeAttempt(oShifter, nPoly, gear, nSeq));
}
