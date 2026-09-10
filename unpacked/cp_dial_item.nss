// cp_dial_item -- Crash Party stress dial: ITEM load.
//
// Spawns a step of junk items on the ground at the venue.
//
// ## Why this dial matters more than it looks
//
// The first profiling pass measured AIUpdateItem at ~92 ms/s on the live realm
// against 0.8 ms/s on an empty one -- items are a disproportionate share of this
// module's AI cost, against an AI update list that is already ~23,400 objects
// (CLAUDE-crash-party.md, "Known before you start"). So this is the dial most
// likely to move the tick rate, and the one to step up most carefully.
//
// It is also why Belt of Infinite Loot was deferred out of the player item set:
// the same load, but sprayed by players with no dial and no off switch.

#include "cp_dm_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!CP_DmGate(oPC)) return;

    object oArea = CP_Venue();
    if (!GetIsObjectValid(oArea)) { SendMessageToPC(oPC, "Venue not found."); return; }

    int nHave = CP_LoadCount();
    if (nHave >= CP_DIAL_CAP)
    {
        SendMessageToPC(oPC, "Load cap reached (" + IntToString(CP_DIAL_CAP)
            + "). Clear before adding more.");
        return;
    }

    int nWant = CP_DIAL_STEP;
    if (nHave + nWant > CP_DIAL_CAP) nWant = CP_DIAL_CAP - nHave;

    // Fail loudly rather than quietly dumping load into the control room: the
    // venue is chosen deliberately (see CP_Venue in cp_dm_inc.nss) and spawning
    // somewhere else would measure the wrong area.
    object oWP = GetWaypointByTag("cp_venue_wp");
    if (!GetIsObjectValid(oWP))
    {
        SendMessageToPC(oPC, "Venue waypoint cp_venue_wp is missing - nothing spawned.");
        return;
    }
    location lAt = GetLocation(oWP);

    int i, nMade = 0;
    for (i = 0; i < nWant; i++)
    {
        // A placeable, not a real item: it produces the same object-count and AI
        // pressure without minting anything a player could pick up, sell or
        // duplicate. Load testing must never put loot on the floor.
        object o = CreateObject(OBJECT_TYPE_PLACEABLE, "plc_barrel", CP_ScatterNear(lAt), FALSE,
                                CP_LOAD_TAG);
        if (GetIsObjectValid(o)) nMade++;
    }

    SendMessageToPC(oPC, "Item dial +" + IntToString(nMade)
        + " (load now " + IntToString(CP_LoadCount()) + "/" + IntToString(CP_DIAL_CAP)
        + "). Watch AIUpdateItem.");
}
