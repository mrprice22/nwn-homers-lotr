 //::///////////////////////////////////////////////
//:: The following on Respawn event is based on
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
void Raise(object oPlayer)
{
        effect eVisual = EffectVisualEffect(VFX_IMP_RESTORATION);

        effect eBad = GetFirstEffect(oPlayer);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectResurrection(),oPlayer);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectHeal(GetMaxHitPoints(oPlayer)), oPlayer);

        //Search for negative effects
        while(GetIsEffectValid(eBad))
        {
            if (GetEffectType(eBad) == EFFECT_TYPE_ABILITY_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_AC_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_ATTACK_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_DAMAGE_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_DAMAGE_IMMUNITY_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_SAVING_THROW_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_SPELL_RESISTANCE_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_SKILL_DECREASE ||
                GetEffectType(eBad) == EFFECT_TYPE_BLINDNESS ||
                GetEffectType(eBad) == EFFECT_TYPE_DEAF ||
                GetEffectType(eBad) == EFFECT_TYPE_PARALYZE ||
                GetEffectType(eBad) == EFFECT_TYPE_NEGATIVELEVEL)
                {
                    //Remove effect if it is negative.
                    RemoveEffect(oPlayer, eBad);
                }
            eBad = GetNextEffect(oPlayer);
        }
        //Fire cast spell at event for the specified target
        SignalEvent(oPlayer, EventSpellCastAt(OBJECT_SELF, SPELL_RESTORATION, FALSE));
        ApplyEffectToObject(DURATION_TYPE_INSTANT, eVisual, oPlayer);
}

object GetMyItem(object oPlayer, int nNumber)
{
    object oItem ;
     switch(nNumber)
        {
        //  Only selects items from the following slots
           case 0:  oItem = GetItemInSlot(INVENTORY_SLOT_CHEST, oPlayer) ; break ;
           case 1:  oItem = GetItemInSlot(INVENTORY_SLOT_BELT, oPlayer) ; break ;
           case 2:  oItem = GetItemInSlot(INVENTORY_SLOT_CLOAK, oPlayer) ; break ;
           case 3:  oItem = GetItemInSlot(INVENTORY_SLOT_HEAD, oPlayer) ; break ;
           case 4:  oItem = GetItemInSlot(INVENTORY_SLOT_LEFTRING, oPlayer) ; break ;
           case 5:  oItem = GetItemInSlot(INVENTORY_SLOT_RIGHTRING, oPlayer) ; break ;
           case 6:  oItem = GetItemInSlot(INVENTORY_SLOT_NECK, oPlayer) ; break ;
           case 7:  oItem = GetItemInSlot(INVENTORY_SLOT_BOOTS, oPlayer) ; break ;
           case 8:  oItem = GetItemInSlot(INVENTORY_SLOT_ARMS, oPlayer) ; break ;
           case 9:  oItem = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPlayer) ; break ;
           case 10: oItem = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPlayer) ; break ;
        }
     if (GetIsObjectValid(oItem)==TRUE)
          { return oItem ; }
     else
          { return OBJECT_INVALID ; }
}

int GetNumber(object oPlayer)
{
    int nAlpha = 0 ;
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_CHEST, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_BELT, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_CLOAK, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_HEAD, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_LEFTRING, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_RIGHTRING, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_NECK, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_BOOTS, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_ARMS, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPlayer))==TRUE){nAlpha++ ; }
     if (GetIsObjectValid(GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPlayer))==TRUE){nAlpha++ ; }
    return nAlpha ;
}
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
//    DelayCommand(2.0, FloatingTextStrRefOnCreature(58299, oDead, FALSE)) ;
//    DelayCommand(2.8, FloatingTextStrRefOnCreature(58300, oDead, FALSE)) ;
}

void main ()
{
object oRespawner = GetLastRespawnButtonPresser() ;
    AssignCommand(oRespawner, ClearAllActions()) ;
        if (GetStandardFactionReputation(STANDARD_FACTION_COMMONER, oRespawner) <= 10)
    {   SetLocalInt(oRespawner, "NW_G_Playerhasbeenbad", 10) ; // * Player bad
        SetStandardFactionReputation(STANDARD_FACTION_COMMONER, 80, oRespawner) ;
    }
    if (GetStandardFactionReputation(STANDARD_FACTION_MERCHANT, oRespawner) <= 10)
    {   SetLocalInt(oRespawner, "NW_G_Playerhasbeenbad", 10) ; // * Player bad
        SetStandardFactionReputation(STANDARD_FACTION_MERCHANT, 80, oRespawner) ;
    }
    if (GetStandardFactionReputation(STANDARD_FACTION_DEFENDER, oRespawner) <= 10)
    {   SetLocalInt(oRespawner, "NW_G_Playerhasbeenbad", 10) ; // * Player bad
        SetStandardFactionReputation(STANDARD_FACTION_DEFENDER, 80, oRespawner) ;
    }
   object oPC = GetLastPlayerDied() ;
     int nOnPC = GetNumber(oPC) ;
        if (nOnPC!=0)
    {
           int nRandom ;
           int nCount=1 ;
           int nHowMany = Random(4) + 1 ;
               if (nOnPC<nHowMany)
                 { nHowMany=nOnPC ; }
           object oSlot ;
    object oMyItem ;
    location locPC = GetLocation(oPC) ;
    // Change "pccorpse" to the tag for your item (if that doesnt work then change it to the resref
    object oBag = CreateObject(OBJECT_TYPE_PLACEABLE, "", locPC) ;
    string sName = GetPCPlayerName(oPC) ;
           SetLocalString(oBag, "sOwner", sName) ;

        while(nCount <= nHowMany)
    {
           nRandom = Random(11) ;
           oMyItem = GetMyItem(oPC, nRandom) ;
               if(GetIsObjectValid(oMyItem)==TRUE)
           {
              AssignCommand(oBag, ActionTakeItem(oMyItem, oPC)) ;
              nCount++ ;
           }
    }
    }


   ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectResurrection(),oRespawner) ;
   ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectHeal(5), oRespawner) ;
   RemoveEffects (oRespawner) ;
  string sDestTag =  "WT_RESPAWN_00" ;
  string sArea = GetTag(GetArea(oRespawner)) ;
 object oSpawnPoint = GetObjectByTag(sDestTag) ;
   AssignCommand(oRespawner,JumpToLocation(GetLocation(oSpawnPoint))) ;
// NO DEATH PENALTY - EVER. Disabled on the admin's call along with the live copy
// that used to sit in mod_respawn.nss (see respawn_inc.nss). This script is not
// hooked to anything today; the call stays commented rather than deleted so it is
// obvious it was switched off on purpose and must not be switched back on.
//   ApplyPenalty(oRespawner) ;

        object oDeathAmulet;
     oDeathAmulet = GetFirstItemInInventory(oRespawner);

     while( GetIsObjectValid( oDeathAmulet ))
     {
        if( GetTag(oDeathAmulet) == "deathamulet" )
        {
           DestroyObject(oDeathAmulet);
           break;
        }
        oDeathAmulet = GetNextItemInInventory(oRespawner);
     }
}

