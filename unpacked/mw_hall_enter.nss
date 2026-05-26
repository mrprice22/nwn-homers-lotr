//::///////////////////////////////////////////////
//:: mw_hall_enter -- Hall of Legends OnEnter handler.
//::
//:: When a PC enters, for each guide the PC has unlocked: if the live
//:: NPC isn't yet spawned, destroy the placeholder statue and spawn the
//:: world-form creature at the statue's location. The swap is permanent
//:: server-side (next PC sees the live guide) -- acceptable for a public
//:: hub area.
//::
//:: Failsafe: if another PC is already present (missed gate, reconnect after
//:: logout, future entrance without occupancy check), the entrant is ejected
//:: to the Well of Eru without disturbing the room state.
//:://////////////////////////////////////////////
#include "mw_unlock_inc"

void TrySwap(string sGuide, object oHallArea)
{
    string sLiveTag = "mw_" + sGuide + "_w";
    object oExisting = GetObjectByTag(sLiveTag);
    // Only skip if the guide is already present in THIS area (GetObjectByTag
    // searches module-wide, so the world-spawn in e.g. Rivendell would
    // otherwise prevent the Hall placement).
    if (GetIsObjectValid(oExisting) && GetArea(oExisting) == oHallArea) return;

    string sStatueTag = "mw_stat_" + sGuide;
    object oStatue = GetObjectByTag(sStatueTag);
    if (!GetIsObjectValid(oStatue)) return;

    float fFacing = GetFacing(oStatue);
    location lLoc = GetLocation(oStatue);
    DestroyObject(oStatue);
    object oNPC = CreateObject(OBJECT_TYPE_CREATURE, sLiveTag, lLoc);
    AssignCommand(oNPC, SetFacing(fFacing));
}

void main()
{
    object oEntering = GetEnteringObject();
    if (!GetIsPC(oEntering)) return;

    object oHallArea = OBJECT_SELF;

    // Failsafe: eject any PC who slips in while another is already here.
    object oOther = GetFirstPC();
    while (GetIsObjectValid(oOther))
    {
        if (oOther != oEntering && GetArea(oOther) == oHallArea)
        {
            SendMessageToPC(oEntering,
                "The Hall of Legends is already occupied by another seeker. "
                + "You have been returned to the Well of Eru.");
            object oWP = GetWaypointByTag("respawn");
            if (GetIsObjectValid(oWP))
            {
                AssignCommand(oEntering, ClearAllActions());
                AssignCommand(oEntering, ActionJumpToLocation(GetLocation(oWP)));
            }
            return;
        }
        oOther = GetNextPC();
    }

    SetLocalInt(GetModule(), "MW_HALL_OCCUPIED", 1);

    MW_SyncJournal(oEntering);

    int i;
    for (i = 0; i < MW_ROSTER_SIZE; i++)
    {
        string sGuide = MW_GuideAt(i);
        if (MW_IsUnlocked(oEntering, sGuide))
            TrySwap(sGuide, oHallArea);
    }
}
