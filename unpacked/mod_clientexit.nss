// mod_clientexit - the module's Mod_OnClientLeav handler.
//
// Split out of hgll_client_exit.nss (roadmap: ll-hgll-split-cliententer). None
// of this is legendary-leveler work: it dismisses lingering epic summons,
// commits any Bank of Bree storage box still carried, snapshots persistent
// state and forces the .bic write.
//
// The leveler itself was deleted in full (roadmap: ll-hgll-remove-scripts), so
// there are no staged level-up picks to drop before the export any more.

#include "pers_state_inc"
#include "bank_box_inc"
#include "epic_summon_inc"
#include "fat_inc"

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
    // Soul-fatigue: freeze the stack queue exactly as it stands. fat_inc also
    // writes on every add and every expiry, so this is belt-and-braces - it
    // only ever catches the <=6s of ticker granularity since the last write.
    // Decay does not run while the character is gone.
    FAT_Save(PC);
    // Force BIC write so the amulet (if any) and any other inventory /
    // BIC-resident state from this session survive a logout that beats
    // the next pc_export_inc auto-save tick.
    ExportSingleCharacter(PC);
}
