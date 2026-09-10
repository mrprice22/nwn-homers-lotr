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
        object o = CreateObject(OBJECT_TYPE_CREATURE, "cp_crashmob",
                                CP_ScatterNear(lAt), FALSE, CP_LOAD_TAG);
        if (GetIsObjectValid(o)) nMade++;
    }

    SendMessageToPC(oPC, "Gatecrashers +" + IntToString(nMade)
        + " (load now " + IntToString(CP_LoadCount()) + "/" + IntToString(CP_DIAL_CAP)
        + "). This is the dial that produces real combat cost - watch the tick rate.");
}
