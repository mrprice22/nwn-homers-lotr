// hgll_client_exit — NWNX:EE port
//
// Originally pushed a queued Letoscript string into the NWNX2 IPC channel on
// logout to mutate the BIC file. With NWNX:EE, HGLL mutations are applied
// in-memory at level-up time and persisted via NWNX_Player_SaveCharacter
// from the leveler dialog itself, so there's nothing to do here.

#include "hgll_func_inc"
#include "pers_state_inc"
#include "bank_box_inc"

void main()
{
    object PC = GetExitingObject();
    // Safety net: if the player logs out mid-session with a Bank of Bree storage
    // box still in inventory (i.e. before finishing the banker dialog), commit it
    // here so the contents are not lost. No-op when no box is carried.
    CommitStrongBoxes(PC, "client_leave");
    CommitFamilyBoxes(PC, "client_leave");
    PersState_Snapshot(PC);
    // Force BIC write so the amulet (if any) and any other inventory /
    // BIC-resident state from this session survive a logout that beats
    // the next pc_export_inc auto-save tick.
    ExportSingleCharacter(PC);
    SetLocalString(PC, "LetoScript", "");
    SetLocalString(PC, "LetoscriptLL", "");
}
