// Forge Warden release gate: TRUE when no illegal gear remains on the PC.
// Reads the cached verdict (FORGE_WARDEN_DIRTY) computed off the dialog hot path
// by the chunked Warden scan; requires FORGE_WARDEN_READY so release is never
// offered before the first verdict is known. Must stay O(1) - see forge_ward_c_il
// for why a synchronous scan here is unsafe.
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetLocalInt(oPC, "FORGE_WARDEN_READY")
        && !GetLocalInt(oPC, "FORGE_WARDEN_DIRTY");
}
