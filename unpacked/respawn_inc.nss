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

/*The following is the basic on respawn for respawn at bind point with exp loss.
PC should respawn with five (5) HP.  Gold is dropped to a bag on the ground that
is lootable by anyone.  Up to 4 random equipped items were dropped on PC death.
those items are lootable only by the owner PC.
*/

#include "nw_i0_plot"
#include "legfeat_inc"

//Get PC Gold and apply XP Penalty
void ApplyPenalty(object oDead)
{
    int nXP = GetXP(oDead) ; //Gets PC's experience
    int nPenalty = 0 * GetHitDice(oDead) ; // Calculates how much experience to lose
    int nHD = GetHitDice(oDead) ; //Gets PC's TOTAL level
// Prevents level loss while respawning and sets new experience
    int nMin = ((nHD * (nHD - 1)) / 2) * 1000 ;
    int nNewXP = nXP - nPenalty ;
    if (nNewXP < nMin)
    nNewXP = nMin ;
    SetXP(oDead, nNewXP) ;
// Takes gold from PC
    int nGoldToTake = FloatToInt(0.10 * GetGold(oDead)) ;
    AssignCommand(oDead, TakeGoldFromCreature(nGoldToTake, oDead, TRUE)) ;
    location nLocDead = GetLocation(oDead) ;// Gets location of death
    // Creates the bag into which the gold is placed.
    object oGoldBag = CreateObject(OBJECT_TYPE_PLACEABLE, "pcgoldbag", nLocDead) ;
     {
    // This creates the gold in the chest just created above:
        object oTarget = GetNearestObjectByTag ("pcgoldbag", oDead, 1) ; // Gets the chest
        string sItemTemplate = "nw_it_gold001" ;  // The standard gold piece
        int nStackSize = nGoldToTake ; // Create gold equal to gold taken on respawn
        CreateItemOnObject(sItemTemplate, oTarget, nStackSize) ; // Makes stack of gold pieces = nGoldToTake, places in chest
     }
    // The next two lines cause the Text "GP Loss" and "XP Loss" to float above the PC AFTER respawn.  Works fine without them.
    DelayCommand(2.0, FloatingTextStrRefOnCreature(58299, oDead, FALSE)) ;
    DelayCommand(2.8, FloatingTextStrRefOnCreature(58300, oDead, FALSE)) ;
}

// Resurrect oPC, put them at the "respawn" waypoint and charge the usual death
// penalty. This is the WHOLE respawn: anything a player gets for clicking the
// Respawn button, a caller of this function gets too.
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
   ApplyPenalty(oPC) ;

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
