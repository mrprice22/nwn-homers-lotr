// Forge Warden release: send the cleared PC back to the Well of Eru.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    // Belt and braces: never release a PC still carrying the flagged contraband.
    // Visibility of this reply is already gated by forge_ward_c_ok (cached
    // verdict), so a cheap single-item re-check on the cached handle is enough -
    // a full ForgeFindIllegalItem scan here would risk the very instruction-cap
    // overflow this fix removes.
    object oBad = GetLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    if (ForgePCHolds(oPC, oBad) && ForgeIsItemIllegal(oBad))
        return;
    DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    object oWP = GetWaypointByTag("secondchance");
    if (!GetIsObjectValid(oWP))
    {
        ForgeLog("forge_ward_rel: waypoint 'secondchance' missing!");
        return;
    }
    location lWell = GetLocation(oWP);
    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, JumpToLocation(lWell));
}
