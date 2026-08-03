// Forge Warden conversation cleanup - wired to the dialog's EndConversation
// AND EndConverAbort hooks, so every new conversation starts from a clean
// slate and forge_ward_intro re-scans the live inventory. Without this the
// cached handles linger on the PC and can be recycled by the engine to
// point at a different item.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC))
        return;
    DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    DeleteLocalObject(oPC, "FORGE_DIS_ITEM");
    DeleteLocalInt(oPC, "FORGE_DIS_COUNT");
    DeleteLocalInt(oPC, "FORGE_DIS_PICK");
    DeleteLocalInt(oPC, "FORGE_RVT_OK");
    // Refresh the cached contraband verdict off the hot path so the NEXT
    // conversation greets from a fresh state (covers items dropped/moved between
    // turns). Chunked, so it can never overflow the instruction cap.
    ForgeBeginWardenScan(oPC);
}
