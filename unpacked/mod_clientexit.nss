// mod_clientexit — the module's Mod_OnClientLeav handler.
//
// Split out of hgll_client_exit.nss (roadmap: ll-hgll-split-cliententer). None
// of this is legendary-leveler work: it dismisses lingering epic summons,
// commits any Bank of Bree storage box still carried, snapshots persistent
// state and forces the .bic write.
//
// The one HGLL-specific step — dropping level-up picks staged by the retired
// leveler before the character is exported — stays in hgll_client_exit.nss and
// is reached by the single ExecuteScript() call below, so retiring the leveler
// (roadmap: ll-hgll-remove-scripts) is a one-line deletion here.

#include "pers_state_inc"
#include "bank_box_inc"
#include "epic_summon_inc"

void main()
{
    object PC = GetExitingObject();
    // Epic summons live in the henchman slot and don't auto-despawn on logout
    // like summoned associates do -- clean up any lingering one here.
    EpicSummon_Dismiss(PC);
    // Safety net: if the player logs out mid-session with a Bank of Bree storage
    // box still in inventory (i.e. before finishing the banker dialog), commit it
    // here so the contents are not lost. No-op when no box is carried.
    CommitStrongBoxes(PC, "client_leave");
    CommitFamilyBoxes(PC, "client_leave");
    PersState_Snapshot(PC);
    // Legacy HGLL residue: a level-up interrupted by a logout leaves its staged
    // picks on the PC, and PC locals ride into the BIC. Drop them before the
    // export so they can never be committed in a later session. Must stay ahead
    // of ExportSingleCharacter. Delete this line together with the hgll_*
    // scripts (ll-hgll-remove-scripts).
    ExecuteScript("hgll_client_exit", PC);
    // Force BIC write so the amulet (if any) and any other inventory /
    // BIC-resident state from this session survive a logout that beats
    // the next pc_export_inc auto-save tick.
    ExportSingleCharacter(PC);
}
