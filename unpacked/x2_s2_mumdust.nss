//::///////////////////////////////////////////////
//:: Mummy Dust
//:: X2_S2_MumDust
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
     Summons a strong warrior mummy for you to
     command.
*/
//:://////////////////////////////////////////////
//:: Created By: Andrew Nobbs
//:: Created On: Feb 07, 2003
//:://////////////////////////////////////////////

#include "x2_inc_spellhook"
#include "epic_summon_inc"

// ---------------------------------------------------------------------------
// Hostile casters get their own reaper, not the player's.
//
// The player half of this spell hands the summon to the HENCHMAN slot, and
// mummyreaper.utc is FactionID 2 (Commoner) precisely so that works. An NPC
// casting the same spell would therefore drop a non-hostile mummy that fights
// nobody -- and, with the default AI's damage retargeting, one its own side can
// end up shooting at. So a non-PC caster creates wtop_mreaper (the same
// creature at FactionID 1) as a plain timed hostile instead.
//
// roadmap wtop-court-combat-defects.
// ---------------------------------------------------------------------------
const string MDUST_NPC_RESREF = "wtop_mreaper";
const string MDUST_NPC_TAG    = "WtopMummyReaper";
const int    MDUST_NPC_MAX    = 2;      // live reapers per area, all casters
const float  MDUST_NPC_LIFE   = 300.0;  // five minutes, then it crumbles

void MDustSummonHostile(object oCaster, location lLoc)
{
    object oArea = GetAreaFromLocation(lLoc);

    // Court-wide cap: several Magi share one pool, so a whole block of them
    // cannot bury a party in mummies.
    int nLive = 0;
    int i = 0;
    object oOld = GetObjectByTag(MDUST_NPC_TAG, i);
    while (GetIsObjectValid(oOld))
    {
        if (GetArea(oOld) == oArea && !GetIsDead(oOld)) nLive++;
        oOld = GetObjectByTag(MDUST_NPC_TAG, ++i);
    }
    if (nLive >= MDUST_NPC_MAX) return;

    object oNew = CreateObject(OBJECT_TYPE_CREATURE, MDUST_NPC_RESREF, lLoc);
    if (!GetIsObjectValid(oNew)) return;

    // Pin its post the way wtop_court.nss does, so leash_to_area sends it back
    // here rather than to wherever the fight drifted.
    SetLocalLocation(oNew, "spawn", lLoc);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_SUMMON_UNDEAD), oNew);

    // Timed on the creature's own queue, so it dies with the creature if the
    // party kills it first.
    AssignCommand(oNew, DelayCommand(MDUST_NPC_LIFE, DestroyObject(oNew)));
}

void main()
{
    /*
      Spellcast Hook Code
      Added 2003-06-20 by Georg
      If you want to make changes to all spells,
      check x2_inc_spellhook.nss to find out more

    */

        if (!X2PreSpellCastCode())
        {
        // If code within the PreSpellCastHook (i.e. UMD) reports FALSE, do not run this spell
            return;
        }

    // An NPC caster (the Weathertop Royal Magus) gets a hostile reaper on its
    // own terms; the player path below is untouched.
    if (!GetIsPC(OBJECT_SELF))
    {
        MDustSummonHostile(OBJECT_SELF, GetSpellTargetLocation());
        return;
    }

    // Epic summon: spawn the mummy reaper as a timed henchman so it can be out
    // alongside a normal summon-animal. See epic_summon_inc.nss.
    EpicSummon_Cast(OBJECT_SELF, "mummyreaper", GetSpellTargetLocation(),
                    HoursToSeconds(30), VFX_FNF_SUMMON_UNDEAD);
}


