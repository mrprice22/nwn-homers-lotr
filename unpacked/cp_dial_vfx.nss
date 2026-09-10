// cp_dial_vfx -- Crash Party stress dial: VISUAL load.
//
// Spawns a step of inert placeables at the venue, each pulsing a permanent VFX.
// This is the cheapest kind of load on the server and the most expensive on the
// client, so it is the dial to reach for first: it tells you where the CLIENTS
// give out, which is a different limit from where the server does.
//
// Everything spawned is tagged CP_LOAD_TAG and is removed by one press of CLEAR
// ALL. Hard capped by CP_DIAL_CAP across all three dials combined.

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
        object o = CreateObject(OBJECT_TYPE_PLACEABLE, "plc_invisobj", CP_ScatterNear(lAt), FALSE,
                                CP_LOAD_TAG);
        if (!GetIsObjectValid(o)) continue;
        ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            EffectVisualEffect(VFX_DUR_AURA_PULSE_YELLOW_WHITE), o);
        nMade++;
    }

    SendMessageToPC(oPC, "VFX dial +" + IntToString(nMade)
        + " (load now " + IntToString(CP_LoadCount()) + "/" + IntToString(CP_DIAL_CAP) + ")");
}
