// cp_dial_mob -- Crash Party stress dial: CREATURE load.
//
// Spawns a step of inert Party Penguins (cp_loadmob) at the venue.
//
// ## What this dial is actually measuring
//
// leash_to_area.nss runs on EVERY area's OnEnter and calls ExecuteScript
// ("bst_install", oCre) for every creature that enters any area -- so a mass
// spawn multiplies that per-creature cost, on top of ordinary AI. That is the
// point: it is the closest safe approximation of "lots of things happening", and
// it is the reason Ring of Recursive Summoning was kept OUT of the player item
// set. A player-driven version of this dial with no cap is how you crash the
// server for real instead of for fun.
//
// The penguins are Commoner faction and Plot: they will not fight anybody and
// nobody can kill them into a pile of corpses. They carry nothing and wear
// nothing -- a pickpocketable spawned NPC is the classic duplication bug.

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
        object o = CreateObject(OBJECT_TYPE_CREATURE, "cp_loadmob", CP_ScatterNear(lAt), FALSE,
                                CP_LOAD_TAG);
        if (GetIsObjectValid(o)) nMade++;
    }

    SendMessageToPC(oPC, "Mob dial +" + IntToString(nMade)
        + " (load now " + IntToString(CP_LoadCount()) + "/" + IntToString(CP_DIAL_CAP)
        + "). Watch AIUpdateCreature and the tick rate.");
}
