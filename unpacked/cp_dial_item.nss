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
    object oPC = CP_DmUser();   // placard OR rest menu
    if (!CP_DmGate(oPC)) return;

    // The console spawns at the venue waypoint; the rest menu spawns around the
    // admin who opened it (CP_DialAnchor). Fail loudly rather than quietly
    // dumping load into the control room.
    object oAnchor = CP_DialAnchor(oPC);
    if (!GetIsObjectValid(oAnchor))
    {
        SendMessageToPC(oPC, "Venue waypoint cp_venue_wp is missing - nothing spawned.");
        return;
    }

    object oArea = GetArea(oAnchor);
    if (!GetIsObjectValid(oArea)) { SendMessageToPC(oPC, "Venue not found."); return; }

    int nHave = CP_LoadCountFor(oAnchor);
    if (nHave >= CP_DIAL_CAP)
    {
        SendMessageToPC(oPC, "Load cap reached (" + IntToString(CP_DIAL_CAP)
            + "). Clear before adding more.");
        return;
    }

    int nWant = CP_DIAL_STEP;
    if (nHave + nWant > CP_DIAL_CAP) nWant = CP_DIAL_CAP - nHave;

    location lAt = GetLocation(oAnchor);

    // Say where it went. Spawning outside the Well of Eru is legitimate from the
    // rest menu, but the venue was picked deliberately (see CP_Venue in
    // cp_dm_inc.nss) -- an area running d_cleartrash.nss measures that sweep
    // rather than the server, so the number deserves a caveat.
    if (oArea != CP_Venue())
        SendMessageToPC(oPC, "Spawning at your position in " + GetName(oArea)
            + " - not the Well of Eru, so compare these numbers with care.");

    int i, nMade = 0;
    for (i = 0; i < nWant; i++)
    {
        // A placeable, not a real item: it produces the same object-count and AI
        // pressure without minting anything a player could pick up, sell or
        // duplicate. Load testing must never put loot on the floor.
        object o = CreateObject(OBJECT_TYPE_PLACEABLE, "plc_barrel", CP_ScatterNear(lAt), FALSE,
                                CP_KEG_TAG);
        if (!GetIsObjectValid(o)) continue;
        nMade++;

        // Stock it. The penguins' rummage behaviour (cp_pengai.nss) walks to the
        // nearest cp_load placeable and drinks, so an empty barrel makes the
        // whole performance look broken. nw_it_mpotion021 is stock Ale -- the
        // same item the module's own Keg of Ale hands out, so no new blueprint.
        int nDrinks = Random(3) + 1;
        int d;
        for (d = 0; d < nDrinks; d++) CreateItemOnObject("nw_it_mpotion021", o);
    }

    SendMessageToPC(oPC, "Item dial +" + IntToString(nMade)
        + " (load now " + IntToString(CP_LoadCountFor(oAnchor)) + "/" + IntToString(CP_DIAL_CAP)
        + "). Watch AIUpdateItem.");
}
