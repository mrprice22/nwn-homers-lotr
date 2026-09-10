// cp_waveup -- Crash Party: release the next wave. Control-room placeable, OnUsed.
//
// CP_WAVE is GLOBAL. Raising it unlocks that wave for everyone at once, and every
// player already standing in the Well is topped up on the spot. Anyone who
// arrives later is caught up on entry by cp_eru_enter.nss -- walk in at wave 3
// and you get waves 0-3 together. There is no per-PC progress gate anywhere in
// this event, deliberately: a grind would punish exactly the latecomers who push
// the concurrency number up.

#include "cp_dm_inc"

void main()
{
    object oPC = CP_DmUser();   // placard OR rest menu
    if (!CP_DmGate(oPC)) return;

    if (!CP_IsOn())
    {
        SendMessageToPC(oPC, "The party is not running. Throw the master switch first.");
        return;
    }

    int nWave = CP_Wave();
    if (nWave >= CP_WAVE_MAX)
    {
        SendMessageToPC(oPC, "Already at the final wave (" + IntToString(CP_WAVE_MAX) + ").");
        return;
    }

    CP_SetWave(nWave + 1);

    // Top up everyone who is already here, so nobody has to walk out and back in.
    int nTouched = 0;
    object oP = GetFirstPC();
    while (GetIsObjectValid(oP))
    {
        if (!GetIsDM(oP) && CP_GrantUpToWave(oP) > 0) nTouched++;
        oP = GetNextPC();
    }

    SendMessageToPC(oPC, "Wave " + IntToString(nWave + 1) + " released; "
        + IntToString(nTouched) + " player(s) topped up on the spot.");
}
