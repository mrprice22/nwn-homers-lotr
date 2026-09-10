// cp_wavedn -- Crash Party: step the wave back down. Control-room placeable.
//
// Only affects what the dispenser will hand out NEXT. It cannot un-give anything:
// items already in a pack stay there with their charges, because nothing in this
// event ever takes an item back. Use it to pause an escalation that is running
// hotter than the tick rate likes.

#include "cp_dm_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!CP_DmGate(oPC)) return;

    int nWave = CP_Wave();
    if (nWave <= 0)
    {
        SendMessageToPC(oPC, "Already at wave 0.");
        return;
    }

    CP_SetWave(nWave - 1);
    SendMessageToPC(oPC, "Wave stepped back to " + IntToString(nWave - 1)
        + ". Nothing already handed out was affected.");
}
