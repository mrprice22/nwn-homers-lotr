// cp_dial_fight -- Crash Party stress dial: COMBAT load.
//
// Spawns a step of hostile Gatecrasher Penguins at the venue.
//
// ## Why this dial exists alongside cp_dial_mob
//
// The other three dials make load that just SITS there -- objects and idle AI.
// Real players generate combat: attack rolls, damage, death, perception checks,
// creatures pathing at moving targets. That is the most expensive thing this
// module does and the closest match to what a crowded party actually costs, so
// it deserves its own dial rather than being approximated by more scenery.
//
// The penguins are deliberately pathetic -- 8 hp, STR 6, CR 1 -- so they cannot
// meaningfully hurt anybody and are worth almost no XP to kill. They carry
// nothing at all: a HOSTILE spawned NPC holding anything real would both be
// pickpocketable and drop it on death.
//
// They share CP_LOAD_TAG with everything else the dials make, so one press of
// CLEAR ALL removes them mid-fight if it gets out of hand.

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
        object o = CreateObject(OBJECT_TYPE_CREATURE, "cp_crashmob",
                                CP_ScatterNear(lAt), FALSE, CP_LOAD_TAG);
        if (GetIsObjectValid(o)) nMade++;
    }

    SendMessageToPC(oPC, "Gatecrashers +" + IntToString(nMade)
        + " (load now " + IntToString(CP_LoadCountFor(oAnchor)) + "/" + IntToString(CP_DIAL_CAP)
        + "). This is the dial that produces real combat cost - watch the tick rate.");
}
