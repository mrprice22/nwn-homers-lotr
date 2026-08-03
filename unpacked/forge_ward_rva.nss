// Forge Warden: revert ALL illegal gear to stock blueprints and, when that
// leaves the PC clean, release them to the Well of Eru. Items with no known
// blueprint stay illegal - the dialog branches to a remains-unlawful entry
// (gated by forge_ward_c_il) and the player must strip those by hand.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    int nFail = ForgeRevertAllIllegal(oPC);
    ForgeLog("forge_ward_rva: " + GetName(oPC) + " revert-all, "
        + IntToString(nFail) + " item(s) had no blueprint");
    // Refresh the cached gate verdict off the hot path. When items remain
    // (nFail > 0) this lets the "still unlawful" branch reflect reality on the
    // next click; when clean we still release immediately below.
    ForgeBeginWardenScan(oPC);
    if (nFail > 0)
        return;
    DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    object oWP = GetWaypointByTag("secondchance");
    if (!GetIsObjectValid(oWP))
    {
        ForgeLog("forge_ward_rva: waypoint 'secondchance' missing!");
        return;
    }
    location lWell = GetLocation(oWP);
    // Delayed so the warden's parting line is on screen before the jump
    // ends the conversation.
    DelayCommand(2.5, AssignCommand(oPC, ClearAllActions()));
    DelayCommand(2.5, AssignCommand(oPC, JumpToLocation(lWell)));
}
