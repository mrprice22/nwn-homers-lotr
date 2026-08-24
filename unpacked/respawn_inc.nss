 //::///////////////////////////////////////////////
//:: respawn_inc -- the module's one respawn implementation.
//:: Extracted from mod_respawn.nss (roadmap
//:: petrification-respawn-defect-round-4) so that more than one caller can
//:: put a dead PC back on their feet at the bind point.
//::
//:: Callers:
//::   mod_respawn.nss  -- Mod_OnSpawnBtnDn, the player clicking Respawn.
//::   pet_respawn.nss  -- the petrification timeout, which cannot ask the
//::                       player to click anything, because the window it
//::                       would have to click is the one the engine already
//::                       put up with Respawn greyed out.
//::
//:: Based on:
//:: Generic On Pressed Respawn Button
//:: Copyright (c) 2001 Bioware Corp.
//:: Created By:   Brent
//:: Created On:   November
//:://////////////////////////////////////////////

/* Respawn at the bind point with five (5) HP and NO penalty of any kind - no
gold, no XP, nothing dropped. The stock comment here used to describe a gold bag
and an XP loss; neither has ever been something this module charged players, and
the last of that code is gone (see below).
*/

#include "nw_i0_plot"
#include "legfeat_inc"

// THERE IS NO DEATH PENALTY IN THIS MODULE, AND THERE NEVER WAS ONE PLAYERS WERE
// TOLD ABOUT. The stock ApplyPenalty() that used to live here took 10% of a
// respawning character's gold and destroyed it -- the "pcgoldbag" placeable it
// tried to drop the gold into does not exist as a blueprint in this module, so
// there was nothing to loot it back out of. Its XP half was already neutered
// (nPenalty = 0 * GetHitDice). Removed outright on the admin's call: respawning
// costs nothing. Do not reintroduce a penalty here -- not for petrification, not
// for a normal death, not "just gold".

// Resurrect oPC and put them at the "respawn" waypoint. This is the WHOLE
// respawn: anything a player gets for clicking the Respawn button, a caller of
// this function gets too.
void LOTR_RespawnPC(object oPC)
{
    if (!GetIsObjectValid(oPC)) return;

   ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectResurrection(),oPC) ;
   ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectHeal(5), oPC) ;
   RemoveEffects (oPC) ;
  string sDestTag =  "respawn" ;
  string sArea = GetTag(GetArea(oPC)) ;
 object oSpawnPoint = GetObjectByTag(sDestTag) ;
   AssignCommand(oPC,JumpToLocation(GetLocation(oSpawnPoint))) ;

   // RemoveEffects above is a WHOLESALE strip, and nothing used to put the
   // permanent bonuses back - so a respawned character silently lost every
   // EFFECT-kind legendary feat (Prowess, Grip, Onslaught, the ability bonuses)
   // until their next login. Found in UAT of the bonus ledger, but it predates
   // it and applies to all of them.
   //
   // Order matters. ClearTransient first: a bard song and a Legendary Reaping
   // kill streak are exactly the bonuses that SHOULD die with the character, and
   // the ledger has to be told, because the song's witness effect was just
   // stripped from under it. LegFeat_ApplyAll then re-registers and re-renders
   // everything permanent. Delayed past the respawn's own effect churn so the
   // rebuild is not undone by it.
   DelayCommand(2.0, BPool_ClearTransient(oPC));
   DelayCommand(2.5, LegFeat_ApplyAll(oPC));

        object oDeathAmulet;
     oDeathAmulet = GetFirstItemInInventory(oPC);

     while( GetIsObjectValid( oDeathAmulet ))
     {
        if( GetTag(oDeathAmulet) == "deathamulet" )
        {
           DestroyObject(oDeathAmulet);
           break;
        }
        oDeathAmulet = GetNextItemInInventory(oPC);
     }
}
