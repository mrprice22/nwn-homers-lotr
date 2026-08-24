//::///////////////////////////////////////////////
//:: Wild Shape
//:: NW_S2_WildShape
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    Allows the Druid to change into animal forms.

    Updated: Sept 30 2003, Georg Z.
      * Made Armor merge with druid to make forms
        more useful.

*/
//:://////////////////////////////////////////////
//:: Created By: Preston Watamaniuk
//:: Created On: Jan 22, 2002
//:://////////////////////////////////////////////
//:: Modified By: Deva Winblood
//:: Modified Date: January 15th-16th, 2008
//:://////////////////////////////////////////////
/*
    Modified to insure no shapeshifting spells are castable upon
    mounted targets.  This prevents problems that can occur due
    to dismounting after shape shifting, or other issues that can
    occur due to preserved appearances getting out of synch.

    This can additional check can be disabled by setting the variable
    X3_NO_SHAPESHIFT_SPELL_CHECK to 1 on the module object.  If this
    variable is set then this script will function as it did prior to
    this modification.

*/

// x3_inc_horse (mounted-abort check) removed: this module has no horse
// system, and the base include chain doesn't compile against the module's
// modified x0_i0_henchman.
#include "shape_merge_inc"

void main()
{
    //Declare major variables
    int nSpell = GetSpellId();
    object oTarget = GetSpellTargetObject();
    effect eVis = EffectVisualEffect(VFX_IMP_POLYMORPH);
    effect ePoly;
    int nPoly;
    int nMetaMagic = GetMetaMagicFeat();
    int nDuration = GetLevelByClass(CLASS_TYPE_DRUID);
    //Enter Metamagic conditions
    if (nMetaMagic == METAMAGIC_EXTEND)
    {
        nDuration = nDuration *2; //Duration is +100%
    }

    //Determine Polymorph subradial type
    if(nSpell == 401)
    {
        nPoly = POLYMORPH_TYPE_BROWN_BEAR;
        if (nDuration >= 12)
        {
            nPoly = POLYMORPH_TYPE_DIRE_BROWN_BEAR;
        }
    }
    else if (nSpell == 402)
    {
        nPoly = POLYMORPH_TYPE_PANTHER;
        if (nDuration >= 12)
        {
            nPoly = POLYMORPH_TYPE_DIRE_PANTHER;
        }
    }
    else if (nSpell == 403)
    {
        nPoly = POLYMORPH_TYPE_WOLF;

        if (nDuration >= 12)
        {
            nPoly = POLYMORPH_TYPE_DIRE_WOLF;
        }
    }
    else if (nSpell == 404)
    {
        nPoly = POLYMORPH_TYPE_BOAR;
        if (nDuration >= 12)
        {
            nPoly = POLYMORPH_TYPE_DIRE_BOAR;
        }
    }
    else if (nSpell == 405)
    {
        nPoly = POLYMORPH_TYPE_BADGER;
        if (nDuration >= 12)
        {
            nPoly = POLYMORPH_TYPE_DIRE_BADGER;
        }
    }
    ePoly = EffectPolymorph(nPoly);
    ePoly = ExtraordinaryEffect(ePoly);
    //Fire cast spell at event for the specified target
    SignalEvent(oTarget, EventSpellCastAt(OBJECT_SELF, SPELLABILITY_WILD_SHAPE, FALSE));

    // Full merge for every form (shape_merge_inc) instead of the vanilla
    // per-form polymorph.2da MergeW/MergeI/MergeA flags.
    struct ShapeMergeGear gear = ShapeMergeSnapshot(OBJECT_SELF);

    // shifter-stats-defect: the form's stock bonus on top of the druid's own
    // stats, linked into ePoly so it ends exactly when the form does. Wrap the
    // finished link, not the bare polymorph, so the top-ups are extraordinary
    // (undispellable) too.
    ePoly = ExtraordinaryEffect(ShapeMergeStatFloor(OBJECT_SELF, nPoly, ePoly, gear));

    //Apply the VFX impact and effects
    ClearAllActions(); // prevents an exploit
    ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, OBJECT_SELF);
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, ePoly, OBJECT_SELF, HoursToSeconds(nDuration));

    ShapeMergeWhenReady(OBJECT_SELF, nPoly, gear);
}
