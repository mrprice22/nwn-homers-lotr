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



void main()
{
    object oPC = GetLastPlayerDied() ;

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
    // Round 4 caveat: this is NOT what rescues a petrified player any more, and
    // must not be treated as though it were. The client will not refresh a death
    // window it is already showing, so the panel the engine disabled at petrify
    // time stays disabled no matter what is sent here - that was the whole of
    // petrification-respawn-defect-round-4. The petrification timeout now
    // respawns the player itself (bleeding.nss -> pet_respawn.nss). This line
    // stays because it is correct for every ORDINARY death.
    DelayCommand(2.5, PopUpDeathGUIPanel(oPC, TRUE, TRUE, 0, "")) ;

}
