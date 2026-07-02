// Forge Warden accusation entry: name the offending item and prime the
// disenchant property list (shared forge_dis_* scripts work off these).
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    // Name the offending item from the cached verdict (set by the jail scan or a
    // prior Warden scan) instead of re-scanning the whole inventory here — the
    // synchronous scan is the instruction-cap hazard we are eliminating. Fall
    // back to one scan only if nothing is cached yet.
    object oBad = GetLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    if (!ForgePCHolds(oPC, oBad) || !ForgeIsItemIllegal(oBad))
        oBad = ForgeFindIllegalItem(oPC);

    if (!GetIsObjectValid(oBad))
    {
        // The cached verdict said DIRTY, but neither the cache nor a fresh
        // scan can back it up now (stale/recycled handle, item moved beyond
        // ForgeFindIllegalItem's reach, or already resolved off-scan). Never
        // accuse on an unconfirmed charge, and never leave <CUSTOM100>/
        // <CUSTOM6119> unset on screen — release instead.
        ForgeLog("forge_ward_intro: DIRTY set but no illegal item resolved for "
            + GetName(oPC) + " -- releasing without judgment.");
        SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", FALSE);
        DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
        object oWP = GetWaypointByTag("secondchance");
        if (GetIsObjectValid(oWP))
        {
            location lWell = GetLocation(oWP);
            DelayCommand(3.0, AssignCommand(oPC, ClearAllActions()));
            DelayCommand(3.0, AssignCommand(oPC, JumpToLocation(lWell)));
        }
        else
            ForgeLog("forge_ward_intro: waypoint 'secondchance' missing!");
        return;
    }
    SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oBad);
    // A stale success flag must not leak into the revert branch gate.
    DeleteLocalInt(oPC, "FORGE_RVT_OK");
    ForgeDisenchantSetup(oPC, oBad);
    SetCustomToken(6119, ForgeLegalStatus(oBad));
    // Refresh the cached gate verdict off the hot path so manual changes since
    // the PC was jailed (e.g. dropping the item) are reflected on the next click.
    ForgeBeginWardenScan(oPC);
}
