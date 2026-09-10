// cp_count -- Crash Party: read the console. Control-room placeable, OnUsed.
//
// The DM-side status line: party state, wave, live load objects, players online
// and the record. Deliberately read-only.
//
// This does NOT replace bin/perfmon -- tick rate is the verdict and that comes
// from the Anvil plugin, not from here. Note the plugin is not deployed on
// season 2 (see the plan's Phase 0b), so on the live realm this counter and
// bin/perf-report are what you have.

#include "cp_dm_inc"

void main()
{
    object oPC = CP_DmUser();   // placard OR rest menu
    if (!CP_DmGate(oPC)) return;

    int nPeak = CP_GetPeak();
    if (nPeak <= 0) nPeak = 8;

    string s = COLOR_YELLOW + "-- CRASH PARTY CONSOLE --" + COLOR_END + "\n";
    s += "Party:   " + (CP_IsOn() ? "RUNNING" : "off") + "\n";
    s += "Wave:    " + IntToString(CP_Wave()) + " of " + IntToString(CP_WAVE_MAX) + "\n";
    s += "Load:    " + IntToString(CP_LoadCount()) + " / " + IntToString(CP_DIAL_CAP)
       + " spawned objects\n";
    s += "Online:  " + IntToString(CP_OnlineCount()) + " (record " + IntToString(nPeak) + ")\n";
    SendMessageToPC(oPC, s);
}
