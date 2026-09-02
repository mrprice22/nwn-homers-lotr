 //::///////////////////////////////////////////////
//:: This script based on:
//:: Death Script
//:: NW_O0_DEATH.NSS
//:: Copyright (c) 2001 Bioware Corp.
//:: Created By: Brent Knowles
//:: Created On: November 6, 2001
//:://////////////////////////////////////////////
/*
    The concept for this script was my idea.  It was a group creation
    effort in the Script Request Forum at http://nwn.bioware.com/forums/
    with a huge ammount of help from Haelix and KJ-Meric.  It also would
    not have been possible for me to have any input into the proccess at all
    were it not for the wonderful people involved in the NWN Lexicon project
    at http://www.reapers.org/nwn/reference/
*/



#include "enr_inc"
#include "bst_db"

void main()
{
    object oPC = GetLastPlayerDied() ;

    // Boss enrage-on-retreat: being killed is not retreating (roadmap
    // boss-enrages-after-killing-player). This must run HERE, at the instant of
    // death, because respawn_inc::LOTR_RespawnPC resurrects and teleports the
    // player to the Well of Eru with no delay - enr_inc's own 6s scan often did
    // not see the corpse at all, and enraged the boss on the player it had just
    // killed.
    ENR_OnPCDied(oPC);

    // Bestiary, the mirror of the kill counter: record which creature did it.
    // Summons, henchmen and animal companions credit their master, the same
    // master-chain walk bst_ondamage does for the other direction.
    object oKiller = GetLastHostileActor(oPC);
    if (!GetIsObjectValid(oKiller)) oKiller = GetLastDamager(oPC);
    while (GetIsObjectValid(GetMaster(oKiller))) oKiller = GetMaster(oKiller);
    Bst_RecordPCDeath(oPC, oKiller);

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

     CreateItemOnObject( "deathamulet" , oPC);
    SetLocalLocation(GetModule(),""+GetName(oPC)+" Death",GetLocation(oPC));

    // Snapshot the BIC right now so a logout-on-death (before the next
    // pc_export_inc auto-save tick) still ships with the amulet present.
    ExportSingleCharacter(oPC);




    // PopUpDeathGUIPanel, NOT PopUpGUIPanel, and the button states are stated
    // rather than inherited ON PURPOSE (roadmap
    // petrification-respawn-defect-round-3). Stock DoPetrification pops this same
    // panel with PopUpDeathGUIPanel(oTarget, FALSE, TRUE, 40579) - Respawn
    // DISABLED - moments before the petrification timeout kills the PC, and the
    // player was left staring at a death window they could not dismiss. Saying
    // TRUE, TRUE here is what re-enables the button. Do not "simplify" this back
    // to PopUpGUIPanel.
    //
    // Round 5 (petrification-respawn-defect-round-5): this line IS what a
    // petrified player gets again - round 4's auto-respawn has been taken back
    // out. Round 4's underlying finding is still true, though: the client will
    // not refresh a death window it is already showing, so this call would land
    // on the engine's greyed-out petrify panel and change nothing. That is why
    // pet_timeout.nss resurrects the PC BEFORE it kills them - the resurrection
    // closes the stale window, so the death below opens a fresh one and the
    // TRUE, TRUE here actually reaches the client. Do not "simplify" this back
    // to PopUpGUIPanel, and do not assume the button states are inherited.
    DelayCommand(2.5, PopUpDeathGUIPanel(oPC, TRUE, TRUE, 0, "")) ;

}
