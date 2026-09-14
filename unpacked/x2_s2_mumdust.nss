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
#include "se_respawn_inc"

// ---------------------------------------------------------------------------
// An NPC's mummy fights for the NPC that summoned it.
//
// The player half of this spell hands the summon to the HENCHMAN slot, and
// mummyreaper.utc is FactionID 2 (Commoner) precisely so that works. An NPC
// cannot use that slot, so the NPC half creates the creature outright and then
// puts it in the CASTER'S OWN faction -- the Weathertop Royal Magus gets a
// hostile reaper exactly as before, and a friendly caster (Gandalf in Hobbiton,
// Saruman) gets one on his side instead of one that turns on him.
//
// Only a Weathertop court caster gets the court-named blueprint. Every other
// NPC gets plain "Epic Mummy Reaper" -- a Mummy Reaper of the Court has no
// business standing in the Shire.
//
// roadmap wtop-court-combat-defects, gandalfs-mummys.
// ---------------------------------------------------------------------------
const string MDUST_WTOP_RESREF = "wtop_mreaper";   // hostile, court-named
const string MDUST_WTOP_TAG    = "WtopMummyReaper";
const string MDUST_NPC_RESREF  = "mummyreaper";    // every other NPC caster
const string MDUST_NPC_TAG     = "NpcMummyReaper"; // NOT "mummyreaper": a PC's
                                                   // henchman reaper carries
                                                   // that tag and must not be
                                                   // counted or cleaned up here
const string MDUST_MASTER      = "MDUST_MASTER";   // who summoned this one
const int    MDUST_CASTER_MAX  = 2;      // live reapers per CASTER
const int    MDUST_NPC_MAX     = 2;      // live reapers per AREA, all casters
const float  MDUST_NPC_LIFE    = 300.0;  // five minutes, then it crumbles

void MDustSummonForNpc(object oCaster, location lLoc)
{
    object oArea = GetAreaFromLocation(lLoc);

    // The court Magus is the only wtop_-prefixed caster; GetResRef is lowercase.
    int bCourt = GetStringLeft(GetResRef(oCaster), 5) == "wtop_";
    string sResRef = bCourt ? MDUST_WTOP_RESREF : MDUST_NPC_RESREF;
    string sTag    = bCourt ? MDUST_WTOP_TAG    : MDUST_NPC_TAG;

    // Two ceilings, counted in one walk of the tag:
    //   per caster - no NPC turns its special-ability uses into an endless
    //                stream of mummies, wherever it is standing;
    //   per area   - several Magi share one court pool, so a whole block of
    //                them cannot bury a party. In the court that one binds
    //                first; anywhere else the per-caster cap is what bites.
    int nArea = 0;
    int nMine = 0;
    int i = 0;
    object oOld = GetObjectByTag(sTag, i);
    while (GetIsObjectValid(oOld))
    {
        if (!GetIsDead(oOld))
        {
            if (GetArea(oOld) == oArea) nArea++;
            if (GetLocalObject(oOld, MDUST_MASTER) == oCaster) nMine++;
        }
        oOld = GetObjectByTag(sTag, ++i);
    }
    if (nArea >= MDUST_NPC_MAX || nMine >= MDUST_CASTER_MAX) return;

    object oNew = CreateObject(OBJECT_TYPE_CREATURE, sResRef, lLoc, FALSE, sTag);
    if (!GetIsObjectValid(oNew)) return;

    // This is a temporary creature: it must never enter the world respawn pool,
    // whatever death script its blueprint carries. wtop_mreaper's chains
    // x2_def_ondeath -> nw_c2_default7 -> SE_DoCreatureRespawn, which would
    // otherwise resurrect it at the summon point forever (roadmap
    // gandalfs-mummys). se_respawn_inc honours this flag.
    SetLocalInt(oNew, SE_NO_RESPAWN, 1);

    // Its summoner's side, whichever side that is.
    ChangeFaction(oNew, oCaster);
    SetLocalObject(oNew, MDUST_MASTER, oCaster);

    // Pin its post the way wtop_court.nss does, so leash_to_area sends it back
    // here rather than to wherever the fight drifted.
    SetLocalLocation(oNew, "spawn", lLoc);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_SUMMON_UNDEAD), oNew);

    // Send it at whatever its summoner is fighting; the default AI takes it
    // from there. Nothing happens if the caster has no foe of its own.
    object oFoe = GetAttackTarget(oCaster);
    if (!GetIsObjectValid(oFoe)) oFoe = GetLastHostileActor(oCaster);
    if (GetIsObjectValid(oFoe) && GetIsEnemy(oFoe, oNew))
        AssignCommand(oNew, ActionAttack(oFoe));

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

    // An NPC caster summons on its own terms -- its own faction, its own caps;
    // the player path below is untouched.
    if (!GetIsPC(OBJECT_SELF))
    {
        MDustSummonForNpc(OBJECT_SELF, GetSpellTargetLocation());
        return;
    }

    // Epic summon: spawn the mummy reaper as a timed henchman so it can be out
    // alongside a normal summon-animal. See epic_summon_inc.nss.
    EpicSummon_Cast(OBJECT_SELF, "mummyreaper", GetSpellTargetLocation(),
                    HoursToSeconds(30), VFX_FNF_SUMMON_UNDEAD);
}


